use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More tests => 17;
use File::Temp qw(tempdir tempfile);
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
    my $result = $logger->OpenLog();
    is($result, 1, 'logfile "STDERR" is converted to stderr sentinel');

    # Verify that Log() actually writes to stderr when sentinel is set
    my ($tmp_fh, $tmp_file) = tempfile(CLEANUP => 1);
    close $tmp_fh;
    open my $save_stderr, '>&', \*STDERR or die "Cannot dup STDERR: $!";
    open STDERR, '>', $tmp_file or die "Cannot redirect STDERR: $!";
    $logger->Log('notice', 'hello stderr test');
    open STDERR, '>&', $save_stderr or die "Cannot restore STDERR: $!";
    close $save_stderr;

    open my $rfh, '<', $tmp_file or die "Cannot read $tmp_file: $!";
    my $content = do { local $/; <$rfh> };
    close $rfh;
    like($content, qr/hello stderr test/, 'STDERR logfile actually writes to stderr');
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

# Test 4: Debug() only logs when debug flag is true
{
    my $dir = tempdir(CLEANUP => 1);
    my $logpath = File::Spec->catfile($dir, 'debug.log');

    my $logger = TestLogger->new(logfile => $logpath, debug => 0);
    $logger->Debug('should not appear');

    ok(!-e $logpath || -z $logpath, 'Debug() suppressed when debug is false');

    my $logger2 = TestLogger->new(logfile => $logpath, debug => 1);
    $logger2->Debug('debug message visible');

    open my $fh, '<', $logpath or die "Cannot read $logpath: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    like($content, qr/debug message visible/, 'Debug() logs when debug flag is true');
}

# Test 5: Error() logs at err level
{
    my $dir = tempdir(CLEANUP => 1);
    my $logpath = File::Spec->catfile($dir, 'error.log');

    my $logger = TestLogger->new(logfile => $logpath);
    $logger->Error('something went wrong');

    open my $fh, '<', $logpath or die "Cannot read $logpath: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    like($content, qr/err.*something went wrong/, 'Error() logs at err level');
}

# Test 6: Fatal() logs and dies
{
    my $dir = tempdir(CLEANUP => 1);
    my $logpath = File::Spec->catfile($dir, 'fatal.log');

    my $logger = TestLogger->new(logfile => $logpath);
    my $died = !eval { $logger->Fatal('fatal error %s', 'happened'); 1 };

    ok($died, 'Fatal() throws an exception');
    like($@, qr/fatal error happened/, 'Fatal() exception contains the formatted message');

    open my $fh, '<', $logpath or die "Cannot read $logpath: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    like($content, qr/fatal error happened/, 'Fatal() logs the message before dying');
}

# Test 7: Log() with format arguments (sprintf-style)
{
    my $dir = tempdir(CLEANUP => 1);
    my $logpath = File::Spec->catfile($dir, 'format.log');

    my $logger = TestLogger->new(logfile => $logpath);
    $logger->Log('notice', 'count=%d name=%s', 42, 'test');

    open my $fh, '<', $logpath or die "Cannot read $logpath: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    like($content, qr/count=42 name=test/, 'Log() applies sprintf formatting to arguments');
}

# Test 8: LogTime() returns a timestamp string
{
    my $logger = TestLogger->new(logfile => 1);
    my $time = $logger->LogTime();
    ok(defined $time && length($time) > 0, 'LogTime() returns a non-empty string');
    like($time, qr/\w+ \w+\s+\d+/, 'LogTime() looks like a localtime string');
}

# Test 9: Log() as class method writes to STDERR
{
    my ($tmp_fh, $tmp_file) = tempfile(CLEANUP => 1);
    close $tmp_fh;
    open my $save_stderr, '>&', \*STDERR or die "Cannot dup STDERR: $!";
    open STDERR, '>', $tmp_file or die "Cannot redirect STDERR: $!";
    Net::Daemon::Log->Log('notice', 'class method call');
    open STDERR, '>&', $save_stderr or die "Cannot restore STDERR: $!";
    close $save_stderr;

    open my $rfh, '<', $tmp_file or die "Cannot read $tmp_file: $!";
    my $content = do { local $/; <$rfh> };
    close $rfh;
    like($content, qr/class method call/, 'Log() as class method writes to STDERR');
}
