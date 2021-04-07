use strict;
use warnings;
use 5.010;
use MetaCPAN::Client;

use Template ();
use DateTime;
#use DateTime::Format::ISO8601;
use Data::Dumper qw(Dumper);
use JSON;

my $tt = Template->new({
    INCLUDE_PATH => './templates',
    INTERPOLATE  => 1,
    WRAPPER      => 'wrapper.tt',
}) or die "$Template::ERROR\n";


main();
exit();

sub main {
    my $now = DateTime->now;
    say $now;
    my $before = $now - DateTime::Duration->new( days => 7 );
    say $before;
    my $start = time;
    my $mcpan = MetaCPAN::Client->new();
    my $all = $mcpan->all('releases', { sort => [{ date => { order => 'desc' } }] });
    #my $all = $mcpan->all('distributions');
    # say $all; # MetaCPAN::Client::ResultSet
    my $total = $all->total;
    say $total;
    my $limit = shift @ARGV;
    my $size = 100;

    my %stats;
    my %distros;

    while (my $release = $all->next) {
        #say $release; # MetaCPAN::Client::Release
        #
        #
        my $distro = $release->distribution;
        next if $distros{$distro};
        $distros{$distro} //= $release;
        #$distros{$distro} //= $release;
        #if ($distros{$distro}->date lt $release->date) {
        #    $distros{$distro} = $release;
        #}

        my $date = $release->date;
        #my $dt = DateTime::Format::ISO8601->parse_datetime( $date );
        #say $date;
        #say $dt > $before;
        #say $release->name;
        #say $release->;
        say $release->author;
        $stats{authors}{$release->author}{count}++;
        last if defined $limit and $limit-- <= 0;
    }
    my @authors =
        map { [$_ => $stats{authors}{$_}] }
        reverse sort {$stats{authors}{$a}{count} <=> $stats{authors}{$b}{count}}
        keys %{ $stats{authors} };
    if (scalar(@authors) > $size) {
        @authors = @authors[0..$size-1];
    }
    for my $auth (@authors) {
        my $author = $mcpan->author($auth->[0]); # https://metacpan.org/pod/MetaCPAN::Client::Author
        $auth->[1]{name} = $author->name;
        $auth->[1]{asciiname} = $author->ascii_name;
    }

    #print Dumper \@authors;
    #say $total;
    my $end = time;

    save_html($total, ($end-$start), $now, \@authors);
    save_data(\%stats);
}

sub save_data {
    my ($data) = @_;
    my $json = JSON->new->allow_nonref;
    open my $fh, '>:encoding(utf8)', 'docs/stats.json' or die $!;
    print $fh $json->pretty->encode( $data );
}

sub save_html {
    my ($total, $elapsed, $now, $authors) = @_;

    my $report;
    $tt->process('stats.tt', {
        total => $total,
        elapsed => $elapsed,
        now => $now,
        authors => $authors,

        #version => $VERSION,
        timestamp => DateTime->now,
    }, \$report) or die $tt->error(), "\n";
    my $html_file = 'docs/stats.html';
    open(my $fh, '>:encoding(utf8)', $html_file) or die "Could not open '$html_file'";
    print $fh $report;
    close $fh;

}

