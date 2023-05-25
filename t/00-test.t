use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use File::Spec ();
use Capture::Tiny qw(capture);


subtest recent => sub {
    my $dir = tempdir( CLEANUP => 1 );
    diag "tempdir: $dir";
    my ($out, $err, $exit) = capture {
        system($^X, '-Ilib', 'bin/cpan-digger', '--data', $dir, '--recent', '2', '--log', 'OFF');
    };

    is $exit, 0;
    is $err, '';
    is $out, '';
};

subtest author => sub {
    my $dir = tempdir( CLEANUP => 1 );
    diag "tempdir: $dir";

    my ($out, $err, $exit) = capture {
        system($^X, '-Ilib', 'bin/cpan-digger', '--data', $dir, '--author', 'SZABGAB', '--log', 'OFF');
    };

    is $exit, 0;
    is $err, '';
    is $out, '';

    # run it again
    ($out, $err, $exit) = capture {
        system($^X, '-Ilib', 'bin/cpan-digger', '--data', $dir, '--author', 'SZABGAB', '--log', 'OFF');
    };

    is $exit, 0;
    is $err, '';
    is $out, '';
};

done_testing();
