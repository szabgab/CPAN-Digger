use strict;
use warnings;
use 5.010;
use MetaCPAN::Client ();
use Getopt::Long qw(GetOptions);
use Data::Dumper qw(Dumper);
use Log::Log4perl ();
use Log::Log4perl::Level ();

my $recent = 10;
my $debug;
GetOptions(
    'recent=s' => \$recent,
    'debug'    => \$debug,
) or die;
my %known_licenses = map {$_ => 1} qw(perl_5);

my $log_level = $debug ? 'DEBUG' : 'INFO';
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority( $log_level ));
my $logger = Log::Log4perl->get_logger();
$logger->info('Starting');

my $report = '';
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
            $subreport .= "resoureces.repository is missing\n";
        }

        if ($subreport) {
            $report .= $item->distribution . "\n";
            $report .= $item->version . "\n";
            $report .= $item->author . "\n";
            $report .= 'https://metacpan.org/release/' . $item->distribution . "\n";
            $report .= $subreport . "\n\n";
        }
}

say "--------------";
say $report;
