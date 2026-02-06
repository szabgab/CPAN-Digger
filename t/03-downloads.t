use strict;
use warnings;

use Capture::Tiny qw(capture);
use File::Temp qw(tempdir);
use Path::Tiny qw(path);

use Test::More;

use CPAN::Digger::CLI;

my $dir = path(tempdir( CLEANUP => 1 ));

subtest process_meta => sub {
    plan tests => 3;

    my $recent = 10;
    diag "fetch the N = $recent most recent releases";
    # some might be two different releases for the same distribution so we can't know for sure how many will be really downloaded.
    my ($out, $err) = capture {
        local @ARGV = ('--data', $dir->child('cpan-digger'), '--repos', $dir->child('repos'), '--recent', $recent, '--log', 'OFF');
        CPAN::Digger::CLI::run();
    };

    is $err, '';
    is $out, '';
    diag qx{tree $dir};

    my $distributions_folder = path($dir)->child('cpan-digger')->child('metacpan')->child('distributions');
    my $iter = $distributions_folder->iterator({
        recurse         => 1,
        follow_symlinks => 0,
    });
    my @files;
    while ( my $path = $iter->() ) {
        next if $path->is_dir;
        push @files, $path;
    }
    cmp_ok scalar(@files), '>=', 1, "no files";
    #diag explain [map {"$_"} @files];
};

done_testing;
