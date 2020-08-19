use strict;
use warnings;
use 5.010;
use Data::Dumper qw(Dumper);
use DateTime;
use DBI;
use File::Spec ();
use FindBin ();
use Getopt::Long qw(GetOptions);
use Log::Log4perl ();
use Log::Log4perl::Level ();
use LWP::UserAgent;
use MetaCPAN::Client ();
use Path::Tiny qw(path);

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
my $html = '
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport"
     content="width=device-width, initial-scale=1, user-scalable=yes">
  <title>CPAN Digger</title>
<style>
.error {
   background-color: red;
}
</style>
</head>
<body>
<h1>CPAN Digger</h1>
<ul>
   <li>Help module authors to ensure that each module that has a public VCS also include a link to it in the meta files.</li>
   <li>Help module authors to link to the preferred bug tracking system.</li>
   <li>Help the projects to have CI system connected to their VCS.</li>
   <li>Help module authors to add a license field to the meta files.</li>
   <li>Help with the new (?) <b>contributing</b> file.</li>
   <li>Suggest to add a Travis-CI badge to the README.md</li>
</ul>
';

my $dbh = get_db();
my $sth_get_distro = $dbh->prepare('SELECT * FROM dists WHERE distribution=?');
my $sth_insert = $dbh->prepare('INSERT INTO dists (distribution, version, author, vcs_url, vcs_name, travis) VALUES (?, ?, ?, ?, ?, ?)');
collect();

$html .= sprintf qq{<hr>Last updated: %s
   <a href="https://github.com/szabgab/cpan-digger-new">Source</a>
</body></html>
}, DateTime->now;
open my $fh, '>', 'index.html' or die;
print $fh $html;
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
    while ( my $item = $rset->next ) {
    		next if $distros{ $item->distribution }; # We have alreay deal with this in this session

            $sth_get_distro->execute($item->distribution);
            my $row = $sth_get_distro->fetchrow_hashref;
            next if $row and $row->{version} eq $item->version; # we already have this in the database (shall we call last?)
            my %data = (
                distribution => $item->distribution,
                version      => $item->version,
                author       => $item->author,
            );

    		$distros{ $item->distribution } = 1;
            $logger->debug('dist: ', $item->distribution);
    		$logger->debug('      ', $item->author);
            #my @licenses = @{ $item->license };
            #$logger->debug('      ', join ' ', @licenses);
            # if there are not licenses =>
            # if there is a license called "unknonws"
            # check against a known list of licenses (grow it later, or look it up somewhere?)
            my %resources = %{ $item->resources };
            #say '  ', join ' ', keys %resources;
            if ($resources{repository}) {
                my ($vcs_url, $vcs_name) = get_vcs($resources{repository});
                if ($vcs_url) {
                    $data{vcs_url} = $vcs_url;
                    $data{vcs_name} = $vcs_name;
                    $logger->debug("      $vcs_name: $vcs_url");
                    if ($vcs_name eq 'GitHub') {
                        $data{travis} = get_travis($vcs_url);
                    }
                }
            } else {
                $logger->warn('No repository for ', $item->distribution);
            }
            say Dumper \%data;
    }
}


sub get_travis {
    my ($url) = @_;
    # TODO: not everyone uses 'master'!
    # TODO: WE might either one to use the API, or clone the repo for other operations as well.
    my $travis_yml = qq{$url/blob/master/.travis.yml};
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $response = $ua->get($travis_yml);
    return $response->is_success;
        #$html .= sprintf qq{<a href="%s">travis.yml</a><br>}, $travis_yml;
    #} else {
        #$html .= qq{<div class="error">Missing Travis-CI configuration file</div>};
    #}
}

sub get_vcs {
    my ($repository) = @_;
    if ($repository) {
        #for my $k (qw(url web)) {
        #    if ($repository->{$k}) {
        #        $html .= sprintf qq{<a href="%s">%s %s</a><br>\n}, $repository->{$k}, $k, $repository->{$k};
        #    }
        #}
        # Try to get the web link
        my $url = $repository->{web};
        if (not $url) {
            $url = $repository->{url};
            $url =~ s{^git://}{https://};
            $url =~ s{\.git$}{};
        }
        my $name = "repository";
        if ($url =~ m{^https?://github.com/}) {
            $name = 'GitHub';
        }
        if ($url =~ m{^https?://gitlab.com/}) {
            $name = 'GitLab';
        }
        return $url, $name;
    }
}

#sub add_to_html {
#    my ($item) = @_;
#    $html .= qq{<div>\n};
#    $html .= sprintf qq{<h2>%s</h2>\n}, $item->distribution;
#    $html .= sprintf qq{<a href="https://metacpan.org/release/%s/%s">%s</a><br>\n}, $item->author, $item->name, $item->distribution;
#    $html .= sprintf qq{<a href="https://metacpan.org/author/%s">%s</a><br>\n}, $item->author, $item->author;
#    my %resources = %{ $item->resources };
#        $html .= sprintf qq{<a href="%s">%s</a><br>\n}, $url, $name;
#        if ($name eq "repository") {
#            $html .= qq{<div class="error">Unknown repo type</div>\n};
#        }
#         $html .= sprintf qq{<a href="%s">travis.yml</a><br>}, $travis_yml;
#            } else {
#
#    } else {
#        $html .= qq{<div class="error">No resources.repository<br>\n};
#    }
#            if ($response->is_success) {
#                $html .= sprintf qq{<a href="%s">travis.yml</a><br>}, $travis_yml;
#            } else {
#                $html .= qq{<div class="error">Missing Travis-CI configuration file</div>};
#            }
#
#    $html .= qq{</div>\n};
#}

sub get_db {
    my $db_file = File::Spec->catdir($FindBin::Bin, 'cpandig.db');
    my $schema_file = File::Spec->catdir($FindBin::Bin, 'schema.sql');
    my $exists = -e $db_file;
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_file", "", "", {
        PrintError       => 0,
        RaiseError       => 1,
        AutoCommit       => 1,
        FetchHashKeyName => 'NAME_lc',
    });
    if (not $exists) {
        my $schema = path($schema_file)->slurp;
        $dbh->do($schema);
    }
    return $dbh
}


sub usage {
    die "Usage: $0
       --recent N
       --debug

       --help
";
}
