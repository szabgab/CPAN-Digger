use strict;
use warnings;

use Capture::Tiny qw(capture);
use File::Copy::Recursive qw(rcopy);
use File::Temp qw(tempdir);
use JSON ();
use Path::Tiny qw(path);
use Test::More;

use CPAN::Digger::CLI;


subtest process_meta => sub {
    plan tests => 3;

    my $dir = path(tempdir( CLEANUP => 1 ));

    my $json = JSON->new->allow_nonref;
    diag "tempdir: $dir";
    my $files = path("t/files");
    rcopy($files->child("metacpan"), $dir->child('cpan-digger')->child('metacpan'));

    my ($out, $err) = capture {
        local @ARGV = ('--data', $dir->child('cpan-digger'), '--repos', $dir->child('repos'), '--meta', '--log', 'OFF');
        CPAN::Digger::CLI::run();
    };

    is $err, '';
    is $out, '';
    #diag qx{tree $dir};
    my $iter = $dir->child('cpan-digger')->child('meta')->iterator({
        recurse => 1,
        follow_symlinks => 0,
    });

    while ( my $path = $iter->() ) {
        next if $path->is_dir;

        my $actual = $json->decode($path->slurp_utf8);
        my $filename = $path->basename;
        my $prefix = $path->parent->basename;
        my $expected = $json->decode( path($files)->child('meta')->child($prefix)->child($filename)->slurp_utf8 );
        is_deeply($actual, $expected, $path);
    }
};

done_testing();

