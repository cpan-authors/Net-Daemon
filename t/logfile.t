use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More tests => 6;
use File::Temp qw(tempdir);
use File::Spec;

use_ok('Net::Daemon::Log');

# Create a minimal object that uses Net::Daemon::Log
{
    package TestLogger;
    our @ISA = ('Net::Daemon::Log');
    sub new {
        my ($class, %attrs) = @_;
        return bless \%attrs, $class;
    }
}

# Test 1: logfile set to a filename string should open the file and log to it
{
    my $dir = tempdir(CLEANUP => 1);
    my $logpath = File::Spec->catfile($dir, 'test.log');

    my $logger = TestLogger->new(logfile => $logpath);
    $logger->Log('notice', 'hello from file test');

    ok(-f $logpath, 'logfile was created when filename string was provided');

    open my $fh, '<', $logpath or die "Cannot read $logpath: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    like($content, qr/hello from file test/, 'log message was written to the file');
}

# Test 2: logfile set to "STDERR" (case-insensitive) should log to stderr
{
    my $logger = TestLogger->new(logfile => 'STDERR');
    # OpenLog should convert "STDERR" to 1 (the stderr sentinel)
    my $result = $logger->OpenLog();
    is($result, 1, 'logfile "STDERR" is converted to stderr sentinel');
}

{
    my $logger = TestLogger->new(logfile => 'stderr');
    my $result = $logger->OpenLog();
    is($result, 1, 'logfile "stderr" is converted to stderr sentinel');
}

# Test 3: logfile set to an IO handle should still work
{
    my $dir = tempdir(CLEANUP => 1);
    my $logpath = File::Spec->catfile($dir, 'handle.log');

    open my $fh, '>>', $logpath or die "Cannot open $logpath: $!";
    my $logger = TestLogger->new(logfile => $fh);
    $logger->Log('notice', 'hello from handle test');
    close $fh;

    open my $rfh, '<', $logpath or die "Cannot read $logpath: $!";
    my $content = do { local $/; <$rfh> };
    close $rfh;

    like($content, qr/hello from handle test/, 'log message was written via IO handle');
}
