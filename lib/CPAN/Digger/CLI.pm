package CPAN::Digger::CLI;
use strict;
use warnings;

our $VERSION = '1.00';

use Getopt::Long qw(GetOptions);

use CPAN::Digger;

sub run {
    my %args = (
        author    => undef,
        github    => undef,
        recent => 10,
        debug  => undef,
        help   => undef,
        sleep  => 0,
    );

    GetOptions(
        \%args,
        'author=s',
        'recent=s',
        'sleep=i',
        'github',
        'debug',
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
       --debug
       --sleep SECONDS    (defaults to 0)
       --github           Fetch information from github

       --help
";
}


42;

