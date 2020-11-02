package CPAN::Digger::CLI;
use strict;
use warnings;

our $VERSION = '1.00';

use Getopt::Long qw(GetOptions);

use CPAN::Digger;

sub run {
    my %args = (
        report => undef,
        author => undef,
        github => undef,
        recent => 10,
        log    => 'OFF',
        help   => undef,
        sleep  => 0,
    );

    GetOptions(
        \%args,
        'author=s',
        'recent=s',
        'sleep=i',
        'github',
        'log=s',
        'report',
        'help',
    ) or usage();
    usage() if $args{help};

    my $cd = CPAN::Digger->new(%args);
    $cd->collect();
}


sub usage {
    die "Usage: $0
       --recent N         (defaults to 10)
       --author PAUSEID
       --report           (Show text report at the end of processing.)
       --log LEVEL        [ALL, TRACE, DEBUG, INFO, WARN, ERROR, FATAL, OFF] (default is OFF)
       --sleep SECONDS    (defaults to 0)
       --github           Fetch information from github

       --help
";
}


42;

