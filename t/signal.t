# -*- perl -*-
#
#   Test that SIGTERM/SIGINT cause graceful shutdown
#

require 5.004;
use strict;
use warnings;
use Test::More;
use POSIX qw/WNOHANG WIFEXITED WEXITSTATUS/;

# Skip on systems without fork
my $can_fork;
eval {
    if ( $^O ne "MSWin32" ) {
        my $pid = fork();
        if ( defined($pid) ) {
            if ( !$pid ) { exit 0; }    # Child
        }
        waitpid( $pid, 0 );
        $can_fork = 1;
    }
};
if ( !$can_fork ) {
    plan skip_all => 'This test requires a system with working forks';
}

plan tests => 6;

use Net::Daemon ();

# Subclass that records whether it reached the "Server terminating" log.
{

    package GracefulTestDaemon;
    our @ISA = qw(Net::Daemon);

    sub Log {
        my ( $self, $level, $fmt, @args ) = @_;
        my $msg = sprintf( $fmt, @args );
        if ( $msg =~ /terminating/ ) {
            $self->{'_terminated_cleanly'} = 1;
        }
    }

    sub Fatal {
        my ( $self, @msg ) = @_;
        die join( ' ', @msg );
    }
}

# Helper: spawn a child daemon, send $signal, verify graceful exit.
# Uses a pipe for synchronization: child writes "R" after socket is
# bound and immediately before calling Bind() (which installs signal
# handlers before entering the accept loop).
sub test_signal {
    my ( $signal, $label ) = @_;

    pipe( my $rd, my $wr ) or die "pipe: $!";

    my $pid = fork();
    die "Cannot fork: $!" unless defined $pid;

    if ( !$pid ) {

        # Child: create a daemon and enter the accept loop
        close $rd;

        my $daemon = bless {
            'mode'     => 'single',
            'proto'    => 'tcp',
            'catchint' => 1,
            'debug'    => 0,
        }, 'GracefulTestDaemon';

        require IO::Socket::INET;
        $daemon->{'socket'} = IO::Socket::INET->new(
            'LocalAddr' => '127.0.0.1',
            'LocalPort' => 0,
            'Proto'     => 'tcp',
            'Listen'    => 1,
            'Reuse'     => 1,
        ) or die "Cannot create socket: $!";

        # Signal parent that we're about to enter Bind().
        # Bind() installs SIGTERM/SIGINT handlers before the accept loop,
        # so by the time the parent reads this and sends the signal,
        # the handlers will be in place.
        syswrite( $wr, "R", 1 );
        close $wr;

        eval { $daemon->Bind() };

        if ( $daemon->{'_terminated_cleanly'} ) {
            exit(42);    # Magic exit code = graceful
        }
        exit(1);
    }

    # Parent: wait for child to be ready
    close $wr;
    my $buf = '';
    sysread( $rd, $buf, 1 );    # Blocks until child signals
    close $rd;

    # Small delay to ensure Bind() has installed signal handlers.
    # The child signals before calling Bind(), so we need a brief
    # window for Bind() to reach the handler installation point.
    select( undef, undef, undef, 0.2 );

    # Send signal
    kill $signal, $pid;

    # Wait for child with timeout
    my $reaped = 0;
    for my $attempt ( 1 .. 100 ) {
        my $ret = waitpid( $pid, WNOHANG );
        if ( $ret > 0 ) {
            $reaped = 1;
            my $status = $?;
            ok( WIFEXITED($status),
                "$label: child exited normally (not killed by signal)" );
            is( WEXITSTATUS($status), 42,
                "$label: child reached graceful shutdown path" );
            last;
        }
        select( undef, undef, undef, 0.1 );
    }
    if ( !$reaped ) {
        kill 'KILL', $pid;
        waitpid( $pid, 0 );
        fail("$label: child exited normally (not killed by signal)");
        fail("$label: child reached graceful shutdown path");
    }
}

# Test 1-2: SIGTERM triggers graceful shutdown
test_signal( 'TERM', 'SIGTERM' );

# Test 3-4: SIGINT triggers graceful shutdown
test_signal( 'INT', 'SIGINT' );

# Test 5-6: Done() is the mechanism — verify it directly
{
    my $daemon = bless { 'mode' => 'single', 'debug' => 0 }, 'Net::Daemon';
    ok( !$daemon->Done(), 'Done() starts as false' );
    $daemon->Done(1);
    ok( $daemon->Done(), 'Done(1) sets the flag' );
}
