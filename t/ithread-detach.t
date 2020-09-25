#!perl

use strict;
use warnings;

use IO::Socket        ();
use Net::Daemon::Test ();

$|  = 1;
$^W = 1;

# Check whether ithreads are available, otherwise skip this test.
if ( !eval { require threads } ) {
    print "1..0 # SKIP This test requires a perl with working ithreads.\n";
    exit 0;
}

my $numTests = 5;

my ( $handle, $port );
if (@ARGV) {
    $port = shift @ARGV;
}
else {
    ( $handle, $port ) = Net::Daemon::Test->Child(
        $numTests,         $^X,              '-Iblib/lib', '-Iblib/arch', 't/server',
        '--mode=ithreads', 'logfile=stderr', 'debug'
    );
}

for ( my $i = 1; $i <= $numTests; $i++ ) {
    eval {
        my $fh = IO::Socket::INET->new(
            'PeerAddr' => '127.0.0.1',
            'PeerPort' => $port
        );
        defined($fh)
          or die "Cannot connect: $!";
        my $result = $fh->getline();
        defined($result)
          or die "Error while reading: " . $fh->error() . " ($!)";
        chomp($result);
        $result =~ /^\d+$/
          or die "Not a number: $result";
        $result <= 1
          or die "Too many active threads: $result";
        $fh->close();
    };
    if ($@) {
        print STDERR $@;
        print "not ok $i\n";
    }
    else {
        print "ok $i\n";
    }

    # Allow some time for threads to clean up.
    sleep(1);
}

END {
    if ($handle) {
        print "Terminating server.\n";
        $handle->Terminate();
        undef $handle;
    }
    unlink "ndtest.prt";
}
