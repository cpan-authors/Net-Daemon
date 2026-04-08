# -*- perl -*-
#
#   Test Accept() access control logic: client masks, accept/deny rules,
#   default behavior, and first-match semantics.
#

use strict;
use warnings;

use Test::More tests => 13;
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
    sub peeraddr { Socket::inet_aton( ${ $_[0] }{'peerhost'} ) }
}

# Helper: build a minimal server object for Accept() testing.
sub make_server {
    my (%overrides) = @_;
    my $server = Net::Daemon->new(
        {
            'pidfile' => 'none',
            'mode'    => 'single',
            'logfile' => 1,         # stderr, avoid syslog
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

# 1. No clients list → accept everyone
{
    my $s = make_server();
    ok( $s->Accept(), 'no clients list accepts all connections' );
}

# 2. Matching accept rule → allow
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '^192\.168\.1\.\d+$', 'accept' => 1 },
        ],
    );
    ok( $s->Accept(), 'matching accept mask allows connection' );
}

# 3. Matching deny rule → reject
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '^192\.168\.1\.\d+$', 'accept' => 0 },
        ],
    );
    ok( !$s->Accept(), 'matching deny mask rejects connection' );
}

# 4. No matching mask → reject (default deny)
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '^10\.0\.0\.\d+$', 'accept' => 1 },
        ],
    );
    ok( !$s->Accept(), 'non-matching mask defaults to deny' );
}

# 5. First-match wins: allow before deny
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '^192\.168\.1\.\d+$', 'accept' => 1 },
            { 'mask' => '.*',                  'accept' => 0 },
        ],
    );
    ok( $s->Accept(), 'first-match wins: allow before catch-all deny' );
}

# 6. First-match wins: deny before allow
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '^192\.168\.1\.\d+$', 'accept' => 0 },
            { 'mask' => '.*',                  'accept' => 1 },
        ],
    );
    ok( !$s->Accept(), 'first-match wins: deny before catch-all allow' );
}

# 7. Catch-all deny at end
{
    my $s = make_server(
        'clients' => [
            { 'mask' => '^10\.0\.0\.\d+$', 'accept' => 1 },
            { 'mask' => '.*',              'accept' => 0 },
        ],
    );
    ok( !$s->Accept(), 'catch-all deny rejects non-matching client' );
}

# 8. Entry with no mask → unconditional match
{
    my $s = make_server(
        'clients' => [
            { 'accept' => 1 },    # no mask = match all
        ],
    );
    ok( $s->Accept(), 'entry without mask acts as unconditional match' );
}

# 9. Entry with no mask and accept=0 → unconditional deny
{
    my $s = make_server(
        'clients' => [
            { 'accept' => 0 },
        ],
    );
    ok( !$s->Accept(), 'entry without mask and accept=0 denies all' );
}

# 10. Multiple masks (arrayref) on single entry
{
    my $s = make_server(
        'clients' => [
            {
                'mask'   => [ '^10\.0\.0\.\d+$', '^192\.168\.' ],
                'accept' => 1,
            },
        ],
    );
    ok( $s->Accept(), 'arrayref of masks: second mask matches' );
}

# 11. Unix socket clients → always resolves to localhost/127.0.0.1
{
    my $s = make_server(
        'proto'   => 'unix',
        'clients' => [
            { 'mask' => '^127\.0\.0\.1$', 'accept' => 1 },
        ],
    );
    ok( $s->Accept(), 'unix socket resolves to 127.0.0.1' );
}

# 12. Unix socket with localhost hostname match
{
    my $s = make_server(
        'proto'   => 'unix',
        'clients' => [
            { 'mask' => '^localhost$', 'accept' => 1 },
        ],
    );
    ok( $s->Accept(), 'unix socket resolves to localhost hostname' );
}
