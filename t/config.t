# -*- perl -*-
#
#   Test access control via config file client masks.
#
require 5.004;
use strict;
use warnings;

use IO::Socket        ();
use Config            ();
use Net::Daemon::Test ();
use Socket            ();
use Test::More;

my $CONFIG_FILE = "t/config";

sub RunTest ($$) {
    my $config   = shift;
    my $numTests = shift;

    my $cf;
    if ( !open( $cf, '>', $CONFIG_FILE ) || !( print $cf $config ) || !close($cf) ) {
        die "Error while creating config file $CONFIG_FILE: $!";
    }

    my ( $handle, $port ) = Net::Daemon::Test->Child(
        $numTests,       $^X,            '-Iblib/lib', '-Iblib/arch', 't/server', '--debug',
        '--mode=single', '--configfile', $CONFIG_FILE
    );
    my $fh = IO::Socket::INET->new(
        'PeerAddr' => '127.0.0.1',
        'PeerPort' => $port
    );
    my $result;
    my $success =
         $fh
      && $fh->print("1\n")
      && defined( $result = $fh->getline() )
      && $result =~ /2/;
    $handle->Terminate();
    $success;
}

my $hostname = gethostbyaddr(
    Socket::inet_aton("127.0.0.1"),
    Socket::AF_INET()
);

if ($hostname) {
    plan tests => 5;
}
else {
    plan tests => 3;
}

ok(
    RunTest( q/{'mode' => 'single', 'timeout' => 60}/, undef ),
    "open client list accepts connection"
);

ok(
    RunTest(
        q/
    { 'mode' => 'single',
      'timeout' => 60,
      'clients' => [ { 'mask' => '^127\.0\.0\.1$', 'accept' => 1 },
                     { 'mask' => '.*', 'accept' => 0 }
                   ]
    }/, undef
    ),
    "accept client matching 127.0.0.1"
);

ok(
    !RunTest(
        q/
    { 'mode' => 'single',
      'timeout' => 60,
      'clients' => [ { 'mask' => '^127\.0\.0\.1$', 'accept' => 0 },
                     { 'mask' => '.*', 'accept' => 1 }
                   ]
    }/, undef
    ),
    "reject client matching 127.0.0.1"
);

if ($hostname) {
    my $regexp = $hostname;
    $regexp =~ s/\./\\\./g;

    ok(
        RunTest(
            q/
        { 'mode' => 'single',
          'timeout' => 60,
          'clients' => [ { 'mask' => '^/
              . $regexp . q/$', 'accept' => 1 },
                         { 'mask' => '.*', 'accept' => 0 }
                       ]
        }/, undef
        ),
        "accept client matching hostname $hostname"
    );

    ok(
        !RunTest(
            q/
        { 'mode' => 'single',
          'timeout' => 60,
          'clients' => [ { 'mask' => '^/
              . $regexp . q/$', 'accept' => 0 },
                         { 'mask' => '.*', 'accept' => 1 }
                       ]
        }/, undef
        ),
        "reject client matching hostname $hostname"
    );
}

END {
    if ( -f "ndtest.prt" ) { unlink "ndtest.prt" }
}
