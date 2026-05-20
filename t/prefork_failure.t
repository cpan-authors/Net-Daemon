# -*- perl -*-
#
# Test that preforking handles fork() failure gracefully
#

use strict;
use warnings;

BEGIN {
    require POSIX;
    our $MOCK_FORK_FAILS_AFTER = -1;
    our $mock_fork_count       = 0;
    *CORE::GLOBAL::fork = sub {
        if ( $MOCK_FORK_FAILS_AFTER < 0 ) {
            return CORE::fork();
        }
        $mock_fork_count++;
        if ( $mock_fork_count > $MOCK_FORK_FAILS_AFTER ) {
            $! = POSIX::EAGAIN();
            return undef;
        }
        return CORE::fork();
    };
}

use Test::More;
use IO::Socket  ();
use Net::Daemon ();

our ( $MOCK_FORK_FAILS_AFTER, $mock_fork_count );

if ( $^O eq 'MSWin32' ) {
    plan skip_all => 'Fork tests not applicable on Windows';
}

# Verify fork override works before proceeding
{
    $MOCK_FORK_FAILS_AFTER = 0;
    $mock_fork_count       = 0;
    my $pid = fork();
    if ( defined $pid ) {
        waitpid( $pid, 0 ) if $pid;
        plan skip_all => 'CORE::GLOBAL::fork override not working';
    }
    $MOCK_FORK_FAILS_AFTER = -1;
    $mock_fork_count       = 0;
}

plan tests => 3;

# Subclass that captures log messages
{

    package PreforkTestDaemon;
    our @ISA = qw(Net::Daemon);

    my @captured;

    sub captured { @captured }
    sub clear    { @captured = () }

    sub Log   { }
    sub Debug { }

    sub Error {
        my $self = shift;
        push @captured, sprintf( shift, @_ );
    }

    sub Fatal {
        my $self = shift;
        my $msg  = sprintf( shift, @_ );
        push @captured, $msg;
        die "$msg\n";
    }
}

# Pre-create listening socket
my $sock = IO::Socket::INET->new(
    'LocalAddr' => '127.0.0.1',
    'LocalPort' => 0,
    'Proto'     => 'tcp',
    'Listen'    => 5,
    'Reuse'     => 1,
);
if ( !$sock ) {
    plan skip_all => "Cannot create socket: $!";
}

# Test 1-2: When all preforking forks fail, Bind() should Fatal
# (not die with an uncaught exception leaving orphan children)
{
    PreforkTestDaemon->clear();

    my $server = PreforkTestDaemon->new(
        {
            'childs'  => 3,
            'pidfile' => 'none',
            'socket'  => $sock,
        },
        []
    );

    $MOCK_FORK_FAILS_AFTER = 0;
    $mock_fork_count       = 0;

    eval { $server->Bind() };

    $MOCK_FORK_FAILS_AFTER = -1;
    $mock_fork_count       = 0;

    like( $@, qr/Cannot fork any child/,
        'Fatal when all preforking forks fail' );

    my @msgs = PreforkTestDaemon->captured();
    my @fork_errs = grep { /Cannot fork child/ } @msgs;
    is( scalar @fork_errs, 1,
        'Error logged for failed fork before Fatal' );
}

# Test 3: Error message includes child number and total
{
    PreforkTestDaemon->clear();

    my $server = PreforkTestDaemon->new(
        {
            'childs'  => 5,
            'pidfile' => 'none',
            'socket'  => $sock,
        },
        []
    );

    $MOCK_FORK_FAILS_AFTER = 0;
    $mock_fork_count       = 0;

    eval { $server->Bind() };

    $MOCK_FORK_FAILS_AFTER = -1;
    $mock_fork_count       = 0;

    my @msgs = PreforkTestDaemon->captured();
    like( $msgs[0], qr/child 1 of 5/,
        'Error message includes child number and total' );
}
