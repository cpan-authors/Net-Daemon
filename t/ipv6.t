# -*- perl -*-
#
#   Test IPv6 support: IO::Socket::IP preference and IPv4-mapped address handling
#
use strict;
use warnings;
use Test::More;

use Net::Daemon;

# Test 1: $INET_CLASS is set
ok( defined $Net::Daemon::INET_CLASS, 'INET_CLASS is defined' );
like( $Net::Daemon::INET_CLASS, qr/^IO::Socket::I(?:NET|P)$/,
    "INET_CLASS is IO::Socket::INET or IO::Socket::IP" );

# Test 2: IO::Socket::IP is preferred when available
SKIP: {
    skip "IO::Socket::IP not available", 1
        unless eval { require IO::Socket::IP; 1 };
    is( $Net::Daemon::INET_CLASS, 'IO::Socket::IP',
        'IO::Socket::IP is preferred when available' );
}

# Test 3-6: Accept() with IPv4-mapped IPv6 addresses in ACL
# Create a mock socket that presents an IPv4-mapped IPv6 address
{
    package MockSocket;
    sub new       { bless { host => $_[1], port => $_[2], addr => $_[3] }, $_[0] }
    sub peerhost  { $_[0]->{host} }
    sub peerport  { $_[0]->{port} }
    sub peeraddr  { $_[0]->{addr} }
}

# Server with IPv4 ACL mask that should match mapped addresses
my $server = Net::Daemon->new(
    {
        'mode'    => 'single',
        'proto'   => 'tcp',
        'clients' => [
            { 'mask' => '^127\.0\.0\.1$', 'accept' => 1 },
            { 'mask' => '.*',             'accept' => 0 },
        ],
    }
);

# Test with plain IPv4 address
$server->{'socket'} = MockSocket->new(
    '127.0.0.1', 12345, Socket::inet_aton('127.0.0.1')
);
ok( $server->Accept(), 'Accept() allows plain IPv4 127.0.0.1' );

# Test with IPv4-mapped IPv6 address
$server->{'socket'} = MockSocket->new(
    '::ffff:127.0.0.1', 12345, Socket::inet_aton('127.0.0.1')
);
ok( $server->Accept(), 'Accept() allows IPv4-mapped ::ffff:127.0.0.1' );

# Test that denied address still rejected
$server->{'socket'} = MockSocket->new(
    '10.0.0.1', 12345, Socket::inet_aton('10.0.0.1')
);
ok( !$server->Accept(), 'Accept() denies non-matching 10.0.0.1' );

# Test denied via mapped address
$server->{'socket'} = MockSocket->new(
    '::ffff:10.0.0.1', 12345, Socket::inet_aton('10.0.0.1')
);
ok( !$server->Accept(), 'Accept() denies non-matching ::ffff:10.0.0.1' );

done_testing();
