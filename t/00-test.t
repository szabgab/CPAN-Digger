use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use File::Spec ();
use Capture::Tiny qw(capture);

my $tempdir = tempdir( CLEANUP => 1 );
diag $tempdir;


$ENV{CPAN_DIGGER_HOME} = $tempdir; #File::Spec->join($tempdir, 'cpandigger');

my ($out, $err, $exit) = capture {
    system($^X, 'bin/cpan-digger');
};

is $exit, 0;
#is $err, '';

done_testing();
