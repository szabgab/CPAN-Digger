use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile);
use Capture::Tiny qw(capture);


subtest downloading_recent_distribtions => sub {
    my $dir = tempdir( CLEANUP => 1 );
    diag "tempdir in downloading_recent_distribtions : $dir";
    my ($out, $err, $exit) = capture {
        system($^X, '-Ilib', 'bin/cpan-digger', '--data', catfile($dir, 'data'), '--repos', catfile($dir, 'repos'), '--recent', '10', '--log', 'OFF');
    };

    is $exit, 0;
    is $err, '', 'STDERR';
    is $out, '', 'STDOUT';

    my $distro_folder = catfile($dir, 'data', 'metacpan', 'distributions');
    ok -e $distro_folder;
    opendir my $dh, $distro_folder or die;
    my @folders = readdir $dh;
    cmp_ok scalar(@folders), '>', 0;
};

subtest downloading_authors => sub {
    my $dir = tempdir( CLEANUP => 1 );
    diag "tempdir in downloading_authors : $dir";

    my ($out, $err, $exit) = capture {
        system($^X, '-Ilib', 'bin/cpan-digger', '--data', catfile($dir, 'data'), '--repos', catfile($dir, 'repos'), '--authors', '--log', 'OFF');
    };

    is $exit, 0;
    is $err, '', 'STDERR';
    is $out, '', 'STDOUT';
    # system "tree $dir";
    my $authors_folder = catfile($dir, 'data', 'metacpan', 'authors');
    ok -e $authors_folder;
    opendir my $dh, $authors_folder or die;
    my @folders = readdir $dh;
    cmp_ok scalar(@folders), '>', 600;
    # this is the number of 2-letter prefixes, it was 625 the last time I ran this
    # the json files are inside those folders
};

done_testing();
