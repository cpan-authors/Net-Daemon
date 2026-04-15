# -*- perl -*-

use strict;
use warnings;

use IO::Socket        ();
use Net::Daemon::Test ();
use Test::More;

my $ok;
eval {
    if ( $^O ne "MSWin32" ) {
        my $pid = fork();
        if ( defined($pid) ) {
            if ( !$pid ) { exit 0; }    # Child
        }
        waitpid( $pid, 0 );
        $ok = 1;
    }
};
if ( !$ok ) {
    plan skip_all => 'This test requires a system with working forks.';
}

plan tests => 6;

my ( $handle, $port );
if (@ARGV) {
    $port = shift @ARGV;
}
else {
    ( $handle, $port ) = Net::Daemon::Test->Child(
        undef,
        $^X, '-Iblib/lib',
        '-Iblib/arch',
        't/server', '--mode=fork',
        '--maxclients=2',
        '--debug', '--timeout', 60
    );
}

# Open two connections that stay alive (at the maxclients limit)
my $fh1 = IO::Socket::INET->new(
    'PeerAddr' => '127.0.0.1',
    'PeerPort' => $port
);
ok( $fh1, 'first connection established' );

my $fh2 = IO::Socket::INET->new(
    'PeerAddr' => '127.0.0.1',
    'PeerPort' => $port
);
ok( $fh2, 'second connection established' );

# Give the server time to fork children for both connections
sleep 1;

# Third connection should be accepted at TCP level (server calls accept())
# but immediately closed by the server because maxclients is reached.
my $fh3 = IO::Socket::INET->new(
    'PeerAddr' => '127.0.0.1',
    'PeerPort' => $port
);

# The TCP connection may succeed (the kernel accept queue allows it),
# but the server closes it immediately. Detect this by trying to
# read — we should get EOF or an error, not a working session.
my $rejected = 0;
if ($fh3) {
    $fh3->print("5\n");
    $fh3->flush();
    my $line = $fh3->getline();
    if ( !defined($line) ) {
        $rejected = 1;    # Server closed connection — maxclients enforced
    }
    $fh3->close();
}
else {
    $rejected = 1;    # Connection refused entirely
}
ok( $rejected, 'third connection rejected (maxclients=2)' );

# Close one connection to free a slot
ok( $fh1->close(), 'first connection closed' );

# Give the server time to reap the child
sleep 2;

# Now a new connection should work
my $fh4 = IO::Socket::INET->new(
    'PeerAddr' => '127.0.0.1',
    'PeerPort' => $port
);
ok( $fh4, 'fourth connection established after slot freed' );

my $exchange_ok = eval {
    $fh4->print("7\n");
    $fh4->flush();
    my $line = $fh4->getline();
    defined($line) && $line =~ /14/;
};
ok( $exchange_ok, 'fourth connection works (multiplier returns 14)' );

$fh2->close() if $fh2;
$fh4->close() if $fh4;

END {
    if ($handle)           { $handle->Terminate() }
    if ( -f "ndtest.prt" ) { unlink "ndtest.prt" }
}
