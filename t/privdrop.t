#!/usr/bin/perl
#
# Test that Bind() detects failed privilege dropping.
#
# On Perl (all versions through 5.42+), assigning to $> (EUID) or $)
# (EGID) silently succeeds even when the underlying setuid()/setgid()
# fails. Net::Daemon::Bind() must verify the change took effect,
# otherwise the daemon continues running with elevated privileges.
#

use strict;
use warnings;
use Test::More;
use IO::Socket ();

# Skip on Windows — no meaningful uid/gid semantics
if ($^O eq 'MSWin32') {
    plan skip_all => 'Privilege dropping is not applicable on Windows';
}

# Skip if running as root — setuid/setgid would actually succeed
if ($> == 0) {
    plan skip_all => 'Cannot test privilege drop failure when running as root';
}

plan tests => 2;

use_ok('Net::Daemon');

# Override Fatal in the correct package (Net::Daemon::Log, inherited by Net::Daemon)
my @fatals;
my $orig_fatal = \&Net::Daemon::Log::Fatal;
{
    no warnings 'redefine', 'prototype';
    *Net::Daemon::Log::Fatal = sub ($$;@) {
        my ($self, $fmt, @args) = @_;
        push @fatals, sprintf($fmt, @args);
        die "Fatal called\n";
    };
}

# Create a daemon object with a --user that differs from our current uid.
# Since we're not root, setuid will fail silently in Perl.
my $bogus_uid = ($> == 65534) ? 65533 : 65534;  # pick a uid != ours
my $self = bless {
    'user'     => $bogus_uid,
    'pidfile'  => 'none',        # skip pidfile logic
    'mode'     => 'single',
    'catchint' => 1,
    'done'     => 1,             # exit accept loop immediately if we get there
    'socket'   => IO::Socket::INET->new(
        'LocalAddr' => '127.0.0.1',
        'LocalPort' => 0,
        'Proto'     => 'tcp',
        'Listen'    => 1,
        'Reuse'     => 1,
    ),
}, 'Net::Daemon';

# Use alarm as safety net against hanging
local $SIG{ALRM} = sub { die "Test timed out — Bind() entered accept loop without privilege check\n" };
alarm(5);

eval { $self->Bind() };
alarm(0);

my $err = $@;

# The daemon should have called Fatal() because privilege drop failed.
# If it didn't, the daemon entered its main loop with elevated privileges.
ok(
    scalar(@fatals) && grep { /UID|uid|setuid|privilege/i } @fatals,
    "Bind() detects failed UID change and calls Fatal()"
) or diag("Expected Fatal about UID change failure, got: ",
          @fatals ? join('; ', @fatals) : "(no Fatal called — daemon ran with wrong UID!)",
          $err ? "\nBind() died with: $err" : "");

# Clean up
$self->{'socket'}->close() if $self->{'socket'};

# Restore
{
    no warnings 'redefine', 'prototype';
    *Net::Daemon::Log::Fatal = $orig_fatal;
}
