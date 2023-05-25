package CPAN::Digger::CLI;
use strict;
use warnings FATAL => 'all';

our $VERSION = '1.04';

use Getopt::Long qw(GetOptions);

use CPAN::Digger;

sub run {
    my %args = (
        report => undef,
        author => undef,
        vcs    => undef,
        recent => undef,
        log    => 'INFO',
        help   => undef,
        sleep  => 0,
        version => undef,
        limit   => undef,
        days    => undef,
        html    => undef,
        data    => 'cpan-digger',
    );

    GetOptions(
        \%args,
        'author=s',
        'recent=i',
        'limit=i',
        'sleep=i',
        'vcs',
        'log=s',
        'report',
        'help',
        'version',
	    'days:i',
        'html=s',
        'data=s',
        'filename=s',
        'distro=s',
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
        --recent N         Number of the most recent packages to check
        --days N

        --author PAUSEID   Get all the released of an author
        --limit N

        --filename path    Get the releases of the distributions listed in the file
        --distro NAME      Get the specific distribution

    Get from VCS
        --vcs              Fetch information from GitHub, GitLab, etc.
        --sleep SECONDS    Wait time between git clone operations, defaults to 0


        --report           Show text report at the end of processing.
        --html DIR         Create HTML pages in the given directory.
        --log LEVEL        [ALL, TRACE, DEBUG, INFO, WARN, ERROR, FATAL, OFF] (default is INFO)

        --data DIR         Provide the folder where we store the data files, defaults to ./cpan-digger

        --version
        --help

    Sample usage for authors:
        $0 --author SZABGAB --report --vcs --sleep 3

    Sample usage in general:
        $0 --recent 30 --report --vcs --sleep 3

};
}


42;

