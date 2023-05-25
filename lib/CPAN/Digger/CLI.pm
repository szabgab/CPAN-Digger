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
        data    => 'data',
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
    ) or usage();
    usage() if $args{help};
    if ($args{version}) {
        print "CPAN::Digger VERSION $VERSION\n";
        exit();
    }
    #usage() if not ($args{author} xor $args{recent} xor $args{filename});


    if ($args{html} and -d $args{html}) {
        print("HTML folder $args{html} already exists. Aborting.\n");
        exit(1);
    }
    my $cd = CPAN::Digger->new(%args);
    $cd->run;
}


sub usage {
    die qq{CPAN::Digger VERSION $VERSION

Usage: $0
    Required exactly one of them:
        --recent N         (Number of the most recent packages to check)
        --days N

        --author PAUSEID
        --limit N

        --filename path/to/file

        --report           (Show text report at the end of processing.)
        --html DIR         Create HTML pages in the given directory.
        --log LEVEL        [ALL, TRACE, DEBUG, INFO, WARN, ERROR, FATAL, OFF] (default is INFO)

        --vcs              Fetch information from github, gitlab
        --sleep SECONDS    (Wait time between git clone operations, defaults to 0)

        --data DIR         Provide the folder where we store the data files, defaults to ./data

        --version
        --help

    Sample usage for authors:
        $0 --author SZABGAB --report --vcs --sleep 3

    Sample usage in general:
        $0 --recent 30 --report --vcs --sleep 3

};
}


42;

