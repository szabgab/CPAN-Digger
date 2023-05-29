package CPAN::Digger::CLI;
use strict;
use warnings FATAL => 'all';

our $VERSION = '1.04';

use Getopt::Long qw(GetOptions);

use CPAN::Digger;

sub run {
    my %args = (
        data     => 'cpan-digger',
        log      => 'INFO',
        sleep    => 0,
    );

    GetOptions(
        \%args,
        'authors',
        'coverage=i',
        'data=s',
        'distro=s',
        'force',
        'help',
        'html=s',
        'limit=i',
        'log=s',
        'meta',
        'metavcs',
        'pull',
        'recent=i',
        'releases',
        'sleep=i',
        'clone=i',
        'version',
    ) or usage();
    usage() if $args{help};
    if ($args{version}) {
        print "CPAN::Digger VERSION $VERSION\n";
        exit();
    }

    my $cd = CPAN::Digger->new(%args);
    $cd->run;
}


sub usage {
    die qq{CPAN::Digger VERSION $VERSION

Usage: $0
    What to get from MetaCPAN:
        --authors          Get all the authors
        --releases         Get all the releases

        --recent N         Number of the most recent packages to check

        --limit N          Limit how many HTML pages are generated

        --distro NAME      Get the specific distribution

        --coverage N       Get the coverage data of N distributions

    Get from VCS
        --clone NUMBER     Fetch information from GitHub, GitLab, etc. for NUMBER projects.
        --sleep SECONDS    Wait time between git clone operations, defaults to 0
        --force            Try to clone even for old releases
        --pull             Try to git pull even if there was no recent release


    Local processing
        --meta             Generate meta files from releases.json files
        --metavcs          Update the meta files from local VCS clones

        --html DIR         Create HTML pages in the given directory.
        --log LEVEL        [ALL, TRACE, DEBUG, INFO, WARN, ERROR, FATAL, OFF] (default is INFO)

        --data DIR         Provide the folder where we store the data files, defaults to ./cpan-digger

        --version
        --help

    Sample usage in general:
        $0 --recent 30 --clone --sleep 3
};
}


42;

