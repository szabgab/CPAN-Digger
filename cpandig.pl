use strict;
use warnings;
use 5.010;
use Data::Dumper qw(Dumper);
use File::Spec ();
use FindBin ();
use Getopt::Long qw(GetOptions);
use Log::Log4perl ();
use Log::Log4perl::Level ();
use MetaCPAN::Client ();


use lib "$FindBin::Bin/lib";
use CPAN::Digger qw(get_data);
use CPAN::Digger::DB qw(db_insert_into db_get_distro get_fields);


my $recent = 10;
my $debug;
my $help;
my $sleep = 0;
GetOptions(
    'recent=s' => \$recent,
    'sleep=i'  => \$sleep,
    'debug'    => \$debug,
    'help'     => \$help,
) or usage();
usage() if $help;

my %known_licenses = map {$_ => 1} qw(perl_5);

collect();

exit;
##########################################################################################

sub collect {
    my $log_level = $debug ? 'DEBUG' : 'INFO';
    Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority( $log_level ));
    my $logger = Log::Log4perl->get_logger();
    $logger->info('Starting');

    my $mcpan = MetaCPAN::Client->new();
    my $rset  = $mcpan->recent($recent);
    my %distros;
    my @fields = get_fields();
    while ( my $item = $rset->next ) {
    		next if $distros{ $item->distribution }; # We have alreay deal with this in this session
            $distros{ $item->distribution } = 1;

            my $row = db_get_distro($item->distribution);
            next if $row and $row->{version} eq $item->version; # we already have this in the database (shall we call last?)
            my %data = get_data($item);
            #say Dumper %data;
            db_insert_into(@data{@fields});
            sleep $sleep if $sleep;
    }
}



sub usage {
    die "Usage: $0
       --recent N         (defaults to 10)
       --debug
       --sleep SECONDS    (defaults to 0)

       --help
";
}
