# -*- perl -*-
#
# Test Net::Daemon->new() constructor option handling

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

use Net::Daemon ();

# --childs forces mode=single
{
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
            'childs'    => 3,
        },
        []
    );
    is( $d->{'mode'}, 'single',
        '--childs forces mode to single' );
    is( $d->{'childs'}, 3,
        '--childs value is preserved' );
}

# --childs via command line args
{
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
        },
        ['--childs=5']
    );
    is( $d->{'mode'}, 'single',
        '--childs from CLI forces mode=single' );
    is( $d->{'childs'}, 5,
        '--childs value from CLI is parsed' );
}

# catchint defaults to 1
{
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
            'mode'      => 'single',
        },
        []
    );
    is( $d->{'catchint'}, 1,
        'catchint defaults to 1' );
}

# --nocatchint disables catchint
{
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
            'mode'      => 'single',
        },
        ['--nocatchint']
    );
    ok( !$d->{'catchint'},
        '--nocatchint disables catchint' );
}

# explicit mode=single is respected
{
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
        },
        ['--mode=single']
    );
    is( $d->{'mode'}, 'single',
        'explicit --mode=single is respected' );
}

# explicit mode=fork is respected (Unix only)
SKIP: {
    skip 'fork mode not available on Windows', 1 if $^O eq 'MSWin32';
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
        },
        ['--mode=fork']
    );
    is( $d->{'mode'}, 'fork',
        'explicit --mode=fork is respected' );
}

# unknown mode is fatal
{
    eval {
        Net::Daemon->new(
            {
                'localport' => 0,
                'mode'      => 'bogus',
            },
            []
        );
    };
    like( $@, qr/Unknown operation mode: bogus/,
        'unknown mode causes Fatal error' );
}

# no $attr defaults to empty hash
{
    my $d = Net::Daemon->new( undef, ['--mode=single'] );
    isa_ok( $d, 'Net::Daemon', 'undef attr creates valid object' );
    is( $d->{'mode'}, 'single',
        'options parsed even with undef attr' );
}

# constructor with no args at all (no option parsing)
{
    my $d = Net::Daemon->new( { 'mode' => 'single' } );
    isa_ok( $d, 'Net::Daemon', 'constructor with no args' );
    is( $d->{'mode'}, 'single',
        'mode from attr preserved with no args' );
}

# non-option args are preserved in $self->{'args'}
{
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
            'mode'      => 'single',
        },
        [ '--debug', 'extra_arg1', 'extra_arg2' ]
    );
    is_deeply(
        $d->{'args'},
        [ 'extra_arg1', 'extra_arg2' ],
        'non-option args preserved in args'
    );
    ok( $d->{'debug'}, '--debug flag parsed' );
}

# ReadConfigFile integration
{
    my $dir = tempdir( CLEANUP => 1 );
    my $cfg = File::Spec->catfile( $dir, 'test.cfg' );
    open my $fh, '>', $cfg or die "Cannot write $cfg: $!";
    print $fh "{ 'mode' => 'single', 'facility' => 'mail' }\n";
    close $fh;

    my $d = Net::Daemon->new(
        {
            'localport' => 0,
        },
        [ "--configfile=$cfg" ]
    );
    is( $d->{'mode'}, 'single',
        'config file sets mode' );
    is( $d->{'facility'}, 'mail',
        'config file sets facility' );
}

# command line options override config file
{
    my $dir = tempdir( CLEANUP => 1 );
    my $cfg = File::Spec->catfile( $dir, 'test.cfg' );
    open my $fh, '>', $cfg or die "Cannot write $cfg: $!";
    print $fh "{ 'mode' => 'single', 'facility' => 'mail' }\n";
    close $fh;

    my $d = Net::Daemon->new(
        {
            'localport' => 0,
        },
        [ "--configfile=$cfg", '--facility=daemon' ]
    );
    is( $d->{'facility'}, 'daemon',
        'CLI option overrides config file' );
}

# ReadConfigFile with non-existent file is fatal
{
    eval {
        Net::Daemon->new(
            {
                'localport' => 0,
                'mode'      => 'single',
            },
            ['--configfile=/nonexistent/path/config.cfg']
        );
    };
    like( $@, qr/No such config file/,
        'non-existent config file is fatal' );
}

# ReadConfigFile with invalid content is fatal
{
    my $dir = tempdir( CLEANUP => 1 );
    my $cfg = File::Spec->catfile( $dir, 'bad.cfg' );
    open my $fh, '>', $cfg or die "Cannot write $cfg: $!";
    print $fh "'not a hash ref'\n";
    close $fh;

    eval {
        Net::Daemon->new(
            {
                'localport' => 0,
                'mode'      => 'single',
            },
            ["--configfile=$cfg"]
        );
    };
    like( $@, qr/did not return a hash ref/,
        'config file returning non-hashref is fatal' );
}

# Done() getter and setter
{
    my $d = Net::Daemon->new(
        {
            'localport' => 0,
            'mode'      => 'single',
        },
        []
    );
    ok( !$d->Done(), 'Done() initially false' );
    $d->Done(1);
    ok( $d->Done(), 'Done(1) sets done flag' );
    $d->Done(0);
    ok( !$d->Done(), 'Done(0) clears done flag' );
}

# Version() returns a string
{
    my $v = Net::Daemon->Version();
    like( $v, qr/Net::Daemon/, 'Version() returns expected string' );
}

# Options() returns expected keys
{
    my $opts = Net::Daemon->Options();
    ok( ref($opts) eq 'HASH', 'Options() returns a hash ref' );
    for my $key (qw(mode debug localport localaddr pidfile user group)) {
        ok( exists $opts->{$key}, "Options() includes '$key'" );
    }
}

# SigChildHandler returns a coderef for fork mode, undef for single
{
    my $d_fork = Net::Daemon->new(
        {
            'localport' => 0,
            'mode'      => 'fork',
        },
        []
    );
    my $ref = \1;
    my $handler = $d_fork->SigChildHandler($ref);
    is( ref($handler), 'CODE',
        'SigChildHandler returns coderef in fork mode' );

    my $d_single = Net::Daemon->new(
        {
            'localport' => 0,
            'mode'      => 'single',
        },
        []
    );
    is( $d_single->SigChildHandler($ref), undef,
        'SigChildHandler returns undef in single mode' );
}

done_testing;
