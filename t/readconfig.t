# -*- perl -*-
#
# Unit tests for ReadConfigFile and config-file integration with new()

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use File::Spec ();

use Net::Daemon ();

# Override Fatal to capture messages without full logging
my @fatals;
{
    no warnings 'redefine', 'prototype', 'once';
    *Net::Daemon::Log::Fatal = sub ($$;@) {
        my ( $self, $fmt, @args ) = @_;
        push @fatals, sprintf( $fmt, @args );
        die "Fatal: $fatals[-1]\n";
    };
}

sub make_daemon {
    bless {
        mode    => 'single',
        pidfile => 'none',
        logfile => 1,
        debug   => 0,
    }, 'Net::Daemon';
}

sub write_config {
    my ($content) = @_;
    my ( $fh, $filename ) = tempfile( UNLINK => 1, SUFFIX => '.conf' );
    print $fh $content;
    close $fh;
    return $filename;
}

# --- Missing config file ---
{
    @fatals = ();
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( '/nonexistent/path/config.cfg', {}, [] ) };
    ok( $@, 'missing file throws exception' );
    like( (defined $fatals[0] ? $fatals[0] : ''), qr/No such config file/, 'missing file error mentions missing file' );
}

# --- Syntax error in config ---
{
    @fatals = ();
    my $file = write_config("{ 'foo' => ");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( $@, 'syntax error throws exception' );
    like( (defined $fatals[0] ? $fatals[0] : ''), qr/Error while processing|did not return a hash ref/,
        'syntax error produces relevant Fatal message' );
}

# --- Returns a scalar instead of hash ref ---
{
    @fatals = ();
    my $file = write_config("42\n");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( $@, 'scalar return throws exception' );
    like( (defined $fatals[0] ? $fatals[0] : ''), qr/did not return a hash ref/, 'scalar return error message' );
}

# --- Returns an array ref ---
{
    @fatals = ();
    my $file = write_config("[1, 2, 3]\n");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( $@, 'array ref return throws exception' );
    like( (defined $fatals[0] ? $fatals[0] : ''), qr/did not return a hash ref/, 'array ref return error message' );
}

# --- Returns undef ---
{
    @fatals = ();
    my $file = write_config("undef\n");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( $@, 'undef return throws exception' );
    like( (defined $fatals[0] ? $fatals[0] : ''), qr/did not return a hash ref/, 'undef return error message' );
}

# --- Returns empty string ---
{
    @fatals = ();
    my $file = write_config("''\n");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( $@, 'empty string return throws exception' );
    like( (defined $fatals[0] ? $fatals[0] : ''), qr/did not return a hash ref/, 'empty string return error message' );
}

# --- Valid config file ---
{
    @fatals = ();
    my $file = write_config("{ 'timeout' => 42, 'facility' => 'mail' }\n");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( !$@, 'valid config file does not throw' ) or diag($@);
    is( $daemon->{'timeout'},  42,     'config sets timeout' );
    is( $daemon->{'facility'}, 'mail', 'config sets facility' );
}

# --- Empty hash ref is valid ---
{
    @fatals = ();
    my $file = write_config("{}\n");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( !$@, 'empty hash ref config is accepted' ) or diag($@);
    is( scalar @fatals, 0, 'no Fatal called for empty hash' );
}

# --- Config values merged into existing attributes ---
{
    @fatals = ();
    my $file = write_config("{ 'facility' => 'mail' }\n");
    my $daemon = make_daemon();
    $daemon->{'pre_existing'} = 'keep';
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( !$@, 'merge does not throw' ) or diag($@);
    is( $daemon->{'facility'},    'mail', 'config adds new attribute' );
    is( $daemon->{'pre_existing'}, 'keep', 'pre-existing attribute preserved' );
}

# --- Config overrides existing values ---
{
    @fatals = ();
    my $file = write_config("{ 'pidfile' => '/var/run/test.pid' }\n");
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( !$@, 'override does not throw' ) or diag($@);
    is( $daemon->{'pidfile'}, '/var/run/test.pid', 'config overrides existing value' );
}

# --- Config with clients array ---
{
    @fatals = ();
    my $file = write_config( q/{
        'clients' => [
            { 'mask' => '^127\\.0\\.0\\.1$', 'accept' => 1 },
            { 'mask' => '.*', 'accept' => 0 }
        ]
    }/ );
    my $daemon = make_daemon();
    eval { $daemon->ReadConfigFile( $file, {}, [] ) };
    ok( !$@, 'config with clients does not throw' ) or diag($@);
    is( ref( $daemon->{'clients'} ), 'ARRAY', 'clients is an array ref' );
    is( scalar @{ $daemon->{'clients'} }, 2, 'clients has 2 entries' );
    is( $daemon->{'clients'}[0]{'accept'}, 1, 'first client accepts' );
    is( $daemon->{'clients'}[1]{'accept'}, 0, 'second client denies' );
}

# --- Integration: new() reads config via --configfile ---
{
    @fatals = ();
    my $file = write_config("{ 'timeout' => 99 }\n");
    my $daemon = Net::Daemon->new(
        { pidfile => 'none', mode => 'single', logfile => 1 },
        [ '--configfile', $file ]
    );
    is( $daemon->{'timeout'}, 99, 'new() with --configfile reads config' );
}

# --- Integration: new() reads config via constructor attr ---
{
    @fatals = ();
    my $file = write_config("{ 'timeout' => 77 }\n");
    my $daemon = Net::Daemon->new(
        { pidfile => 'none', mode => 'single', logfile => 1, configfile => $file },
        []
    );
    is( $daemon->{'timeout'}, 77, 'new() with configfile attr reads config' );
}

# --- Integration: command-line options override config file values ---
{
    @fatals = ();
    my $file = write_config("{ 'mode' => 'fork', 'timeout' => 30 }\n");
    my $daemon = Net::Daemon->new(
        { pidfile => 'none', logfile => 1 },
        [ '--configfile', $file, '--mode=single' ]
    );
    is( $daemon->{'mode'},    'single', 'CLI --mode overrides config file mode' );
    is( $daemon->{'timeout'}, 30,       'config file value preserved when no CLI override' );
}

# --- Integration: constructor attrs < config file < CLI options ---
{
    @fatals = ();
    my $file = write_config("{ 'localport' => 9999 }\n");
    my $daemon = Net::Daemon->new(
        { pidfile => 'none', mode => 'single', logfile => 1, localport => 1111 },
        [ '--configfile', $file ]
    );
    is( $daemon->{'localport'}, 9999,
        'config file overrides constructor attr' );
}

done_testing;
