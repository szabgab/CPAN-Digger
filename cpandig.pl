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
use Template;

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

my $dbh = get_db();
my $sth_get_distro = $dbh->prepare('SELECT * FROM dists WHERE distribution=?');
my $sth_get_every_distro = $dbh->prepare('SELECT * FROM dists');
my @fields = qw(distribution version author vcs_url vcs_name travis github_actions);
my $fields = join ', ', @fields;
my $sth_insert = $dbh->prepare("INSERT INTO dists ($fields) VALUES (?, ?, ?, ?, ?, ?, ?)");
collect();
generate_html();

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
                        if (not $data{travis}) {
                            $data{github_actions} = get_github_actions($vcs_url);
                        }
                    }
                }
            } else {
                $logger->warn('No repository for ', $item->distribution);
            }
            #say Dumper \%data;
            $sth_insert->execute(@data{@fields});
    }
}


sub get_github_actions {
    my ($url) = @_;
    return _check_url(qq{$url/tree/master/.github/workflows});
}

sub get_travis {
    my ($url) = @_;
    # TODO: not everyone uses 'master'!
    # TODO: WE might either one to use the API, or clone the repo for other operations as well.
    return _check_url(qq{$url/blob/master/.travis.yml});
}

sub _check_url {
    my ($url) = @_;
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $response = $ua->get($url);
    return $response->is_success;
}


sub get_vcs {
    my ($repository) = @_;
    if ($repository) {
        #        $html .= sprintf qq{<a href="%s">%s %s</a><br>\n}, $repository->{$k}, $k, $repository->{$k};
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

sub generate_html {
    my ($item) = @_;

#            $html .= qq{<div class="error">Unknown repo type</div>\n};

    $sth_get_every_distro->execute;
    my @distros;
    while (my $row = $sth_get_every_distro->fetchrow_hashref) {
        push @distros, $row;
    }

    my %data = (
        timestamp     => DateTime->now,
        distributions => \@distros,
    );

    my $tt = Template->new({
        INCLUDE_PATH => File::Spec->catdir($FindBin::Bin, 'templates'),
        INTERPOLATE  => 1,
    }) or die "$Template::ERROR\n";

    my $html;
    $tt->process('main.tt', \%data, \$html) or die $tt->error(), "\n";

    open my $fh, '>', 'index.html' or die "Could not open file for writing $!";
    print $fh $html;
}

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
