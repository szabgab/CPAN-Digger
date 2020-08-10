use strict;
use warnings;
use 5.010;
use MetaCPAN::Client ();
use Getopt::Long qw(GetOptions);
use Data::Dumper qw(Dumper);
use Log::Log4perl ();
use Log::Log4perl::Level ();
use DateTime;

my $recent = 10;
my $debug;
my $help;
GetOptions(
    'recent=s' => \$recent,
    'debug'    => \$debug,
    'help'     => \$help,
) or usage();
usage() if $help;

my %known_licenses = map {$_ => 1} qw(perl_5);
my $report = '';
my $html = '
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport"
     content="width=device-width, initial-scale=1, user-scalable=yes">
  <title>CPAN Digger</title>
</head>
<body>
<h1>CPAN Digger</h1>
<ul>
   <li>Help module authors to ensure that each module that has a public VCS also include a link to it in the meta files.</li>
   <li>Help module authors to link to the preferred bug tracking system.</li>
   <li>Help the projects to have CI system connected to their VCS.</li>
   <li>Help module authors to add a license field to the meta files.</li>
   <li>Help with the new (?) <b>contributing</b> file.</li>
</ul>
';


collect();
report();

$html .= sprintf qq{<hr>Last updated: %s
   <a href="https://github.com/szabgab/cpan-digger-new">Source</a>
</body></html>
}, DateTime->now;
open my $fh, '>', 'index.html' or die;
print $fh $html;

sub collect {
    my $log_level = $debug ? 'DEBUG' : 'INFO';
    Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority( $log_level ));
    my $logger = Log::Log4perl->get_logger();
    $logger->info('Starting');

    my $mcpan = MetaCPAN::Client->new();
    my $rset  = $mcpan->recent($recent);
    my %distros;
    while ( my $item = $rset->next ) {
    		next if $distros{ $item->distribution };

            my $subreport = '';
    		$distros{ $item->distribution } = 1;
            $logger->debug('dist: ', $item->distribution);
    		$logger->debug('      ', $item->author);
            my @licenses = @{ $item->license };
            $logger->debug('      ', join ' ', @licenses);
            # if there are not licenses =>
            # if there is a license called "unknonws"
            # check against a known list of licenses (grow it later, or look it up somewhere?)
            my %resources = %{ $item->resources };
            #say '  ', join ' ', keys %resources;
            if ($resources{repository}) {
                #$logger->debug('      repository:', sort keys %{ $resources{repository} });  # web, url, type
                $logger->debug('      repository: ', $resources{repository}{url});
            } else {
                $logger->warn('No repository for ', $item->distribution);
                $subreport .= "resources.repository is missing\n";
            }

            add_to_html($subreport, $item);
            if ($subreport) {
                $report .= $item->distribution . "\n";
                $report .= $item->version . "\n";
                $report .= $item->author . "\n";
                $report .= 'https://metacpan.org/release/' . $item->distribution . "\n";
                $report .= $subreport . "\n\n";
            }
    }
}

sub add_to_html {
    my ($subreport, $item) = @_;
    $html .= qq{<div>\n};
    $html .= sprintf qq{<h2>%s</h2>\n}, $item->distribution;
    $html .= sprintf qq{<a href="https://metacpan.org/release/%s/%s">%s</a><br>\n}, $item->author, $item->name, $item->distribution;
    $html .= sprintf qq{<a href="https://metacpan.org/author/%s">%s</a><br>\n}, $item->author, $item->author;
    my %resources = %{ $item->resources };
    if ($resources{repository}) {
        $html .= sprintf qq{<a href="%s">repository</a><br>\n}, $resources{repository}{url};
    } else {
        $html .= qq{<div class="error">No resources.repository<br>\n};
    }

    $html .= qq{</div>\n};
}

sub report {
    say "--------------";
    say $report;
}

sub usage {
    die "Usage: $0
       --recent N
       --debug

       --help
";
}
