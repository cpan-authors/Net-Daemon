# -*- perl -*-
#
#   Test Accept() edge cases: invalid regex masks, gethostbyaddr failures,
#   and missing peer identity.
#

use strict;
use warnings;

use Test::More tests => 8;
use IO::Socket ();

use_ok('Net::Daemon');

# A mock socket that returns controlled peerhost/peerport/peeraddr values.
{
    package MockSocket;
    our @ISA = qw(IO::Socket);

    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub peerhost { ${ $_[0] }{'peerhost'} }
    sub peerport { ${ $_[0] }{'peerport'} }
    sub peeraddr { Socket::inet_aton( ${ $_[0] }{'peerhost'} || '127.0.0.1' ) }
}

# Helper: build a minimal server object for Accept() testing.
sub make_server {
    my (%overrides) = @_;
    my $server = Net::Daemon->new(
        {
            'pidfile' => 'none',
            'mode'    => 'single',
            'logfile' => 1,    # stderr, avoid syslog
            %overrides,
        },
        []
    );
    $server->{'socket'} ||= MockSocket->new(
        'peerhost' => '192.168.1.42',
        'peerport' => 9999,
    );
    $server->{'proto'} ||= 'tcp';
    return $server;
}

# 1. Invalid regex mask does not crash the daemon
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '*invalid[', 'accept' => 1 },
        ],
    );
    my $result;
    eval { $result = $s->Accept(); };
    is( $@, '', 'invalid regex mask does not die' );
    ok( !$result, 'invalid regex mask denies access (fail-closed)' );
}

# 2. Invalid regex mask is skipped, valid mask still matches
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '(unclosed',          'accept' => 0 },
            { 'mask' => '^192\.168\.1\.\d+$', 'accept' => 1 },
        ],
    );
    my $result;
    eval { $result = $s->Accept(); };
    is( $@, '', 'invalid mask followed by valid mask does not die' );
    ok( $result, 'valid mask still matches after invalid mask is skipped' );
}

# 3. Multiple masks per client, one invalid
{
    my $s = make_server(
        'clients' => [
            {
                'mask'   => [ '+broken', '^192\.168\.1\.\d+$' ],
                'accept' => 1,
            },
        ],
    );
    my $result;
    eval { $result = $s->Accept(); };
    is( $@, '', 'array mask with one invalid entry does not die' );
    ok( $result, 'valid mask in array still matches' );
}

# 4. Empty patterns list (simulated via unix proto override with undef peerhost)
#    This tests the defensive check when gethostbyaddr fails and peerhost is undef.
{
    # Create a mock socket with undef peerhost to simulate DNS failure
    my $broken_socket = MockSocket->new(
        'peerhost' => undef,
        'peerport' => 9999,
    );
    my $s = make_server(
        'clients' => [ { 'mask' => '.*', 'accept' => 1 } ],
    );
    # Override to non-unix so it goes through gethostbyaddr path
    $s->{'proto'}  = 'tcp';
    $s->{'socket'} = $broken_socket;

    # gethostbyaddr on inet_aton('127.0.0.1') should still work on most systems,
    # but if peerhost returns undef, our fallback should handle it gracefully.
    my $result;
    eval { $result = $s->Accept(); };
    is( $@, '', 'accept with broken peer identity does not die' );
}
