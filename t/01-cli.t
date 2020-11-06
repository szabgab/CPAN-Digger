use strict;
use warnings;

use Test::More;
use Mock::Quick qw(qclass);
use Storable qw(dclone);
use Capture::Tiny qw(capture);
use Path::Tiny qw(path);

use MetaCPAN::Client::Release;


# TODO: Shall we test the case that the resureces method does not return any hash?

my @results_recent = (
    {
        'date' => '2020-11-04T12:01:11',
        'distribution' => 'Robin-Hood',
        'version' => '1.01',
        'resources' => {
        },
    },
    {
        'date' => '2020-11-04T10:31:20',
        'distribution' => 'Princess Fiona',
        'version' => '2.03',
        'resources' => {
        },
    },
#   {
#     'date' => '2020-11-04T09:51:50',
#     'distribution' => 'Zorg',
#     'version' => '3.21',
#   },
);


#my @results_author = (
#   {
#     'date' => '2020-11-04T12:01:11',
#     'distribution' => 'Mars-Base',
#     'version' => '1.11'
#   },
#   {
#     'date' => '2020-11-04T10:31:20',
#     'distribution' => 'Moon-Base',
#     'version' => '2.22'
#   },
#   {
#     'date' => '2020-11-04T09:51:50',
#     'distribution' => 'Earth',
#     'version' => '3.33'
#   }
#);



sub my_next {
    my ($self) = @_;
    my $res = shift @{$self->{results}};
    return if not $res;

    my $obj = MetaCPAN::Client::Release->new(%$res);
    return $obj;
}

sub recent {
    my ($self, $limit) = @_;
    return _result_set(@results_recent);
}
#sub releases {
#    my ($self) = @_;
#    return _result_set(@results_author);
#}

#sub author {
#    return MetaCPAN::Client::Author->new;
#}

sub _result_set {
    my (@results) = @_;
    my $rs = MetaCPAN::Client::ResultSet->new;
    $rs->{results} = dclone(\@results);
    return $rs;
}


my $client;
my $resultset;
#my $author;
BEGIN {
    $client = qclass(
        -implement => 'MetaCPAN::Client',
        -with_new => 1,
        recent => \&recent,
#        author => \&author,
    );
    $resultset = qclass(
        -implement => 'MetaCPAN::Client::ResultSet',
        -with_new => 1,
        next => \&my_next,
    );
#    $author = qclass(
#        -implement => 'MetaCPAN::Client::Author',
#        -with_new => 1,
#        releases => \&releases,
#    );
}


use CPAN::Digger::CLI;


subtest recent_in_memory => sub {
    my ($out, $err, $exit) = capture {
        local @ARGV = ('--recent', '2', '--report', '--log', 'OFF');
        CPAN::Digger::CLI::run();
    };

    is $err, '', 'STDERR';
    my $expected_out = path('t/files/recent_in_memory.out')->slurp;
    is $out, $expected_out, 'STDOUT';
    if ($ENV{SAVE}) {
        path('t/files/recent_in_memory.out')->spew($out);
    }
};

done_testing();
