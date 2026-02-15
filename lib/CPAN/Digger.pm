package CPAN::Digger;
use strict;
use warnings FATAL => 'all';
use feature 'say';

our $VERSION = '1.04';

use Capture::Tiny qw(capture);
use Cwd qw(getcwd);
use Data::Dumper qw(Dumper);
use Data::Structure::Util qw(unbless);
use DateTime         ();
use DateTime::Duration;
use DateTime::Format::ISO8601;
use Exporter qw(import);
use File::Copy::Recursive qw(rcopy);
use File::Spec::Functions qw(catfile);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use JSON ();
use List::MoreUtils qw(uniq);
use Log::Log4perl ();
use LWP::UserAgent ();
use MetaCPAN::Client ();
use Module::CoreList;
use Path::Tiny qw(path);
use PAUSE::Permissions;
use Storable qw(dclone);
use Template ();
use List::Util qw( min max );

my $TOP_DEPENDENCY_PAGE = 100;
my $git = 'git';
my $root = getcwd();

my @ci_names = qw(appveyor azure_pipeline bitbucket_pipeline circleci github_actions gitlab_pipeline jenkins travis);

# Authors who indicated (usually in an email exchange with Gabor) that they don't have public VCS and are not
# interested in adding one. So there is no point in reporting their distributions.
my %no_vcs_authors = map { $_ => 1 } qw(PEVANS NLNETLABS RATCLIFFE JPIERCE GWYN JOHNH LSTEVENS GUS KOBOLDWIZ STRZELEC TURNERJW MIKEM MLEHMANN YHPENG);

# Authors that are not interested in CI for all (or at least for some) of their modules
my %no_ci_authors = map { $_ => 1 } qw(SISYPHUS GENE PERLANCAR);

my %no_ci_distros = map { $_ => 1 } qw(Kelp-Module-Sereal);

my %known_licenses = map {$_ => 1} qw(agpl_3 apache_1_1 apache_2_0 artistic_1 artistic_2 bsd freebsd gpl_1 gpl_2 gpl_3 lgpl_2_1 lgpl_3_0 mit mozilla_1_1 perl_5);
# open_source, unknown, restricted, unrestricted, zlib

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    for my $key (keys %args) {
        if ($key eq 'clone') {
            $self->{clone_vcs} = $args{clone};
            next;
        }
        if ($key eq 'authors') {
            $self->{download_authors} = $args{authors};
            next;
        }
        if ($key eq 'dashboard') {
            $self->{pull_dashboard} = $args{dashboard};
            next;
        }
        if ($key eq 'permissions') {
            $self->{download_permissions} = $args{permissions};
            next;
        }
        $self->{$key} = $args{$key};
    }
    $self->{log} = uc $self->{log};
    $self->{total} = 0;
    $self->{dependencies} = {};
    $self->{authors} = {};
    $self->{dashboard_path} = 'dashboard';
    $self->{reverse_dependency} = {};

    my $dt = DateTime->now;
    $self->{start_time} = $dt;
    $self->{data} = $args{data}; # data folder where we store the json files
    mkdir "logs";
    mkdir $self->{repos};
    make_path "$self->{data}/meta";
    make_path "$self->{data}/metacpan/distributions";
    make_path "$self->{data}/metacpan/authors";
    make_path "$self->{data}/metacpan/coverage";

    return $self;
}

sub run {
    my ($self) = @_;


    $self->setup_logger($self->{start_time}, $self->{logname}, $self->{screen});
    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info('CPAN::Digger started');

    $self->download_authors_from_metacpan;
    $self->download_permission;

    my $rset = $self->search_releases_on_metacpan;
    $self->get_release_data_from_metacpan($rset);

    $self->download_cpants;

    $self->get_coverage_data;
    $self->update_meta_data_from_releases;

    $self->clone_vcs;
    $self->check_files_on_vcs;

    $self->pull_dashboards;

    $self->html;

    my $end = DateTime->now;
    my ($minutes, $seconds) = ($end-$self->{start_time})->in_units('minutes', 'seconds');
    $logger->info("CPAN:Digger ended. Elapsed time: $minutes minutes $seconds seconds");
}

sub setup_logger {
    my ($self, $start, $prefix, $screen) = @_;

    my $log_level = $self->{log}; # TODO: shall we validate?
    my $logfile = $start->strftime("%Y-%m-%d-%H-%M-%S");

    my $conf = qq(
      log4perl.appender.Logfile          = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.filename = logs/$prefix-$logfile.log
      log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Logfile.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss} [%r] %F %L %p %m%n
    );

    if ($screen) {
        $conf .= qq(
      log4perl.category.digger           = $log_level, Logfile, Screen
      log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
      log4perl.appender.Screen.stderr  = 0
      log4perl.appender.Screen.layout  = Log::Log4perl::Layout::SimpleLayout
       );
    } else {
        $conf .= qq(
      log4perl.category.digger           = $log_level, Logfile
      );
    }

    # avoid creating empty log file when the logger is OFF:
    if ($log_level eq 'OFF') {
        $conf = qq(
          log4perl.category.digger           = $log_level, Screen
          log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
          log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout
        );
    }

    Log::Log4perl::init( \$conf );

}

sub download_permission {
    my ($self) = @_;

    return if not $self->{download_permissions};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Download permissions file");

    my $ua = LWP::UserAgent->new(timeout => 5);

    my $perms_uri = "https://cpan.org/modules/06perms.txt";
    my $permission_file = catfile($self->{data}, '06perms.txt');
    my $response = $ua->mirror($perms_uri, $permission_file);

    $logger->info("Download permissions file '$permission_file' ended");

}

sub download_authors_from_metacpan {
    my ($self) = @_;

    return if not $self->{download_authors};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Download authors from MetaCPAN");

    my @authors;
    my $mcpan = MetaCPAN::Client->new();
    my $all = $mcpan->all('authors'); # ~ 14374
    my $dir = "$self->{data}/metacpan/authors";
    while (my $author = $all->next) {
        my $pauseid = uc $author->pauseid;
        my $prefix = substr($pauseid, 0, 2);
        my $filename = catfile($dir, $prefix, "$pauseid.json");

        mkdir catfile($dir, $prefix);
        $logger->info("Saving to $filename");
        save_data($filename, $author);
    }
    $logger->info("Download authors from MetaCPAN finished");
}

sub load_authors {
    my ($self) = @_;
    my @prefixes = read_dir("$self->{data}/metacpan/authors");
    for my $prefix (@prefixes) {
        my @files = read_dir("$self->{data}/metacpan/authors/$prefix");
        for my $file (@files) {
            my $author = read_data("$self->{data}/metacpan/authors/$prefix/$file");
            $self->{authors}{ $author->{pauseid} } = $author;
        }
    }
}

sub metacpan_stats {
    #my $mcpan = MetaCPAN::Client->new();

    # Foo-Bar is a distribution
    # Foo-Bar-0.02 is a release
    # Total numbers collected on 2023.05.27
    #my $all = $mcpan->all('releases');  # 365966
    #my $all = $mcpan->all('authors'); # 14374
    #my $all = $mcpan->all('modules'); # 28882019
    #my $all = $mcpan->all('distributions'); # 44213
    #my $all = $mcpan->all('favorites'); # 47071
    #my $all = $mcpan->release( { status => 'latest' }); # 39230
    #say $all->total;
    # say $all; # MetaCPAN::Client::ResultSet
}


sub search_releases_on_metacpan {
    my ($self) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Recent: $self->{recent}") if $self->{recent};
    $logger->info("Distribution $self->{distro}") if $self->{distro};
    $logger->info("All the releases") if $self->{releases};

    my $mcpan = MetaCPAN::Client->new();
    my $rset;
    if ($self->{distro}) {
        $rset = $mcpan->release({
            either => [{ distribution => $self->{distro} }]
        });
    } elsif ($self->{recent}) {
        $rset  = $mcpan->recent($self->{recent});
    } elsif ($self->{releases}) {
        $rset = $mcpan->release( { status => 'latest' }); # ~ 39230
    } else {
        #die "How did we get here?";
        return;
    }
    $logger->info("MetaCPAN::Client::ResultSet received with a total of $rset->{total} releases");
    return $rset;
}

sub get_release_data_from_metacpan {
    my ($self, $rset) = @_;

    return if not $rset;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Get releases from metacpan");

    my $mcpan = MetaCPAN::Client->new();

    my $skip_releases = 0;
    while ( my $release = $rset->next ) {
        if ($release->{data}{status} ne 'latest') {
            $skip_releases++;
            next;
        }
        #$logger->info("Release: " . $release->name);
        #$logger->info("Distribution: " . $release->distribution);
        my $distribution =  lc $release->distribution;
        my $prefix = substr($distribution, 0, 2);
        mkdir catfile($self->{data}, 'metacpan', 'distributions', $prefix);
        my $data_file = catfile($self->{data}, 'metacpan', 'distributions', $prefix, "$distribution.json");
        $logger->info("data file $data_file");
        save_data($data_file, $release);
    }
    $logger->info("Skipped releases: $skip_releases") if $skip_releases;

    $logger->info("Get releases from metacpan ended");
}

sub read_dir {
    my ($dir) = @_;

    opendir(my $dh, $dir) or die "Could not open directory $dir. $!";
    my @entries = grep { $_ ne '.' and $_ ne '..' } readdir $dh;
    closedir $dh;
    return @entries;
}


sub get_all_meta_filenames {
    my ($self) = @_;

    my $dir = catfile($self->{data}, 'meta');
    my @prefixes = read_dir($dir);

    my @filenames;
    for my $prefix (@prefixes) {
        push @filenames, map { catfile($dir, $prefix, $_) } read_dir(catfile($dir, $prefix));
    }

    return @filenames;
}


sub get_all_distribution_filenames {
    my ($self) = @_;

    my $dir = catfile($self->{data}, 'metacpan', 'distributions');
    my @prefixes = read_dir($dir);

    my @filenames;
    for my $prefix (@prefixes) {
        push @filenames, map { catfile($dir, $prefix, $_) } read_dir(catfile($dir, $prefix));
    }

    return @filenames;
}

sub update_meta_data_from_releases {
    my ($self) = @_;

    return if not $self->{meta};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Update meta data from the releases");

    my @distribution_filenames = $self->get_all_distribution_filenames;
    my $counter = 0;
    for my $distribution_file (@distribution_filenames) {
        my $distribution_data = read_data($distribution_file);
        my $prefix = substr(basename($distribution_file), 0, 2);
        mkdir catfile($self->{data}, 'meta', $prefix);
        my $coverage_filename = catfile($self->{data}, 'metacpan', 'coverage', $prefix, basename($distribution_file));
        my $coverage = read_data($coverage_filename);

        my $meta_filename = catfile($self->{data}, 'meta', $prefix, basename($distribution_file));
        $logger->info("distribution $distribution_file => $meta_filename");
        my $distribution = $distribution_data->{distribution};
        $logger->debug("distribution: $distribution");
        my $repository = $distribution_data->{data}{resources}{repository};
        my $meta = read_data($meta_filename);
        $meta->{distribution} = $distribution_data->{distribution};
        $meta->{release_date} = $distribution_data->{data}{date};
        $meta->{version}      = $distribution_data->{data}{version};
        $meta->{author}       = $distribution_data->{data}{author};
        $meta->{cover_total}  = $coverage->{total};

        if ($repository) {
            my ($real_vcs_url, $folder, $name, $vendor) = $self->get_vcs($repository, $distribution);
            if ($vendor) {
                $meta->{vcs_url} = $real_vcs_url;
                $meta->{vcs_folder} = lc $folder;
                $meta->{vcs_name} = $name;
                $meta->{vcs_vendor} = $vendor;
                $logger->info("VCS: $vendor $real_vcs_url");
            }
            $self->get_bugtracker($distribution_data->{data}{resources}, $meta);
            my @licenses = @{ $distribution_data->{data}{license} };
            $meta->{licenses} = join ' ', @licenses;
            $logger->info("      $meta->{licenses}");
            for my $license (@licenses) {
                if ($license eq 'unknown') {
                    $logger->error("Unknown license '$license' for $distribution");
                } elsif (not exists $known_licenses{$license}) {
                    $logger->warn("Unknown license '$license' for $distribution. Probably CPAN::Digger needs to be updated");
                }
            }
            # if there are not licenses =>
            # if there is a license called "unknown"
        } else {
            $logger->error("distribution $distribution has no repository");
        }

        # update kwalitee from cpants
        my $cpants_file = catfile($self->{data}, 'cpants', $prefix, basename($distribution_file));
        my $cpants = read_cpants_file($cpants_file);
        if (%$cpants) {
            $meta->{core_kwalitee} = $cpants->{data}{metadata}{kwalitee}{core_kwalitee};
        }

        save_data($meta_filename, $meta);
    }

    #$data->{vcs_last_checked} = 0;

    ## $logger->info("status: $release->{data}{status}");
    ## There are releases where the status is 'cpan'. They can be in the recent if for example they dev releases
    ## with a _ in their version number such as Astro-SpaceTrack-0.161_01
    $logger->info("Update meta data from the releases ended");
}

sub get_coverage_data {
    my ($self) = @_;

    return if not $self->{coverage};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Get coverage data from MetaCPAN");

    my $mcpan = MetaCPAN::Client->new();

    my @distribution_filenames = $self->get_all_distribution_filenames;
    my $counter = 0;
    for my $distribution_file (@distribution_filenames) {
        #$logger->info("distribution_file: $distribution_file");
        my $distribution_data = read_data($distribution_file);
        my $release = $distribution_data->{data}{name};
        my $date = $distribution_data->{data}{date};
        $logger->info("name: $release at $date");

        my $prefix = substr(basename($distribution_file), 0, 2);
        mkdir catfile($self->{data}, 'metacpan', 'coverage', $prefix);
        #my $distribution = $distribution_data->{distribution});
        my $coverage_filename = catfile($self->{data}, 'metacpan', 'coverage', $prefix, basename($distribution_file));

        # If we don't receive any coverage data from MetaCPAN we can't know if this is because the coverage data has not arrived yet
        # or because there will never be coverage data for this distribution.
        # We don't want to ask for coverage data forever so we have to decide how much we are ready to hope for it to arrive.
        # Hence the following
        # If there is coverage file and coverage data for the current release we don't fetch.
        # If there is coverage file, not coverage data, and TIME has passed since the date of this release, we don't fetch.
        my $TIME = DateTime::Duration->new(days => 1);

        my $old_criteria = read_data($coverage_filename);
        next if %$old_criteria and $old_criteria->{release} eq $release and exists $old_criteria->{total};
        next if %$old_criteria and $old_criteria->{release} eq $release and $date lt $self->{start_time} - $TIME;

        $logger->info("Fetching coverage for $release");
        my $cover = $mcpan->cover($release);
        my $report = $cover->criteria;
        $report->{release} = $release;
        save_data($coverage_filename, $report);

        last if ++$counter >= $self->{coverage};
    }

    $logger->info("Get coverage data from MetaCPAN ended");
}

sub clone_vcs {
    my ($self) = @_;

    return if not $self->{clone_vcs};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Clone VCSes");

    my @meta_filenames = $self->get_all_meta_filenames;
    my $counter = 0;
    for my $meta_file (@meta_filenames) {
        my $meta = read_data($meta_file);
        next if not $meta->{vcs_url};

        $self->clone_one_vcs($meta->{vcs_url}, $meta->{vcs_folder}, $meta->{vcs_name}, $meta->{distribution}, $meta->{release_date});

        last if ++$counter >= $self->{clone_vcs};

        sleep $self->{sleep} if $self->{sleep};
    }

    $logger->info("Clone VCSes ended");
}

sub clone_one_vcs {
    my ($self, $vcs_url, $folder, $name, $distribution, $release_date) = @_;

    my $logger = Log::Log4perl::get_logger("digger");
    $logger->info("Cloning $vcs_url to $folder");

    # When we first clone we would like to clone all the repos (we will use the force)
    # Later we would like to attempt to clone only repos of distros that were relesead in the last N minutes.
    # We would also like to pull only repos of distros that were released in the last M days.
    # The problem is that if someone removes travis and adds GitHub Actions (or makes any other change to the git repository)
    # without releasing a new verssion - which can happen to someone who would only want to modernize the infrastructurs
    # We won't be able to show this.
    # Time measurements on 2023.05.29 on the server where CPAN Digger runs of `git pull` on a GitHub-based project that has nothing to bring.
    # `time git pull` shows  0.245s   if the remote is https://github.com
    # `time git pull` shows  0.726s   if the remote is git@github.com
    # the logs indicate 260 ms  (based on the %r report of Log::Log4perl
    # On 2023.05.29
    # find cpan-digger/metacpan/distributions/ | grep json | wc    indicates 39,195 entries
    # ll repos/*/* | grep ^d | wc      indicates that that there are 16,118 repositories.
    # CPAN.Rocks indicates 39,209 distributions, 13,538 of them having git. 32 hg, 21 svn
    # So if we execute git pull on all the 13,538 repos it will take about 3384 sec, roughly 1 hour.
    my $TIME_TO_CLONE = DateTime::Duration->new(days => 1);
    my $TIME_TO_PULL = DateTime::Duration->new(days => 7);
    my $release_dt = DateTime::Format::ISO8601->parse_datetime($release_date);

    make_path $folder;
    my @cmd;
    my $named_folder = catfile($folder, $name);
    if (-e $named_folder) {
        $logger->info("git pull as '$named_folder' already exists");
        my $time_to_pull = $self->{start_time} - $TIME_TO_PULL;
        if (not $self->{pull} and $release_dt lt $time_to_pull) {
            $logger->info("Release date '$release_dt' is less than time_to_pull: '$time_to_pull'. Not pulling.");
            return;
        }
        # TODO: check if the vcs_url is the same as our remote or if it has moved; we can update the remote easily

        chdir $named_folder;
        @cmd = ($git, "pull");
    } else {
        $logger->info("git clone");
        my $time_to_clone = $self->{start_time} - $TIME_TO_CLONE;
        if (not $self->{force} and $release_dt lt $time_to_clone) {
            $logger->info("Release date '$release_dt' is less than time_to_clone: '$time_to_clone'. Not cloning.");
            return;
        }
        my $vcs_is_accessible = check_repo($vcs_url, $distribution);
        if (not $vcs_is_accessible) {
            $logger->error("VCS is not accessible. Not cloning.");
            return;
        }

        chdir $folder;
        @cmd = ($git, "clone", "--depth", "1", $vcs_url);
    }

    $logger->info("cmd: @cmd");
    my ($out, $err, $exit_code) = capture {
        system(@cmd);
    };
    chdir($root);
    if ($exit_code) {
        $logger->error("exit code: $exit_code in command '@cmd' distribution $distribution");
        $logger->error("stdout: $out");
        $logger->error("stderr: $err");
        return;
    }

    return;
}

sub pull_dashboards {
    my ($self) = @_;

    return if not $self->{pull_dashboard};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Pull dashboard");
 
    if (not -e $self->{dashboard_path}) {
        system "$git clone --depth 1 https://github.com/davorg/dashboard.git";
    } else {
        chdir $self->{dashboard_path};
        system "git pull";
        chdir "..";
    }

    $logger->info("Pull dashboard ended");
}

sub read_dashboards {
    my ($self) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Read dashboard");

    $self->{dashboards} = { map { substr(basename($_), 0, -5) => 1 } glob "$self->{dashboard_path}/authors/*.json" };

    $logger->info("Read dashboard ended");
}

sub get_vcs {
    my ($self, $repository, $distribution) = @_;

    my $logger = Log::Log4perl->get_logger('digger');

    return if not $repository;

    # Try to get the web link
    my $url = $repository->{web};
    if (not $url) {
        $url = $repository->{url};
        if (not $url) {
            $logger->error("No URL found in distribution $distribution");
            return;
        }
    }

    $url = lc $url;
    $url =~ s{^git://}{https://};
    $url =~ s{^http://}{https://};
    $url =~ s{\.git$}{};

    my $vendor = "repository";
    my $git_url;
    if ($url =~ m{https://(github\.com|gitlab\.com|bitbucket\.org)/([a-zA-Z0-9-]+)/([a-zA-Z0-9_.-]+)}) {
        my $vendor_host = $1;
        my $owner = $2;
        my $name = $3;
        $vendor = substr($vendor_host, 0, -4);
        $vendor = 'GitHub' if $vendor eq "github";
        $vendor = 'GitLab' if $vendor eq "gitlab";
        $vendor = 'Bitbucket' if $vendor eq "bitbucket";
        $git_url = "https://$vendor_host/$owner/$name";
        my $folder = catfile($self->{repos}, $vendor, $owner);
        return $git_url, $folder, $name, $vendor;
    }

    $logger->error("Unrecognized vendor for $url in distribution $distribution");
    return $url, '', '', $vendor;
}

sub get_bugtracker {
    my ($self, $resources, $data) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    if (not $resources->{bugtracker} or not $resources->{bugtracker}{web}) {
        $logger->error("No bugtracker for $data->{distribution}");
        return;
    }
    $data->{issues} = $resources->{bugtracker}{web};

    if ($data->{issues} =~ m{http://}) {
        my $vcs_url = $data->{vcs_url} // '';
        $logger->warn("Bugtracker URL $data->{issues} is http and not https. VCS is: $vcs_url");
    }
}

sub check_repo {
    my ($vcs_url, $distribution) = @_;

    my $logger = Log::Log4perl->get_logger('digger');

    my $ua = LWP::UserAgent->new(timeout => 5);
    my $response = $ua->get($vcs_url);
    my $status_line = $response->status_line;
    if ($status_line eq '404 Not Found') {
        $logger->error("Repository '$vcs_url' of distribution $distribution Received 404 Not Found. Please update the link in the META file");
        return;
    }
    if ($response->code != 200) {
        $logger->error("Repository '$vcs_url' of distribution $distribution got a response of '$status_line'. Please report this to the maintainer of CPAN::Digger.");
        return;
    }
    if ($response->redirects) {
        $logger->error("Repository '$vcs_url' of distribution $distribution is being redirected. Please update the link in the META file");
        return;
    }

    return 1;
}


sub analyze_bitbucket {
    my ($data, $repo) = @_;

    $data->{bitbucket_pipeline} = -e "$repo/bitbucket-pipelines.yml";
    $data->{travis} = -e "$repo/.travis.yml";
    $data->{jenkins} = -e "$repo/Jenkinsfile";
}


sub analyze_gitlab {
    my ($data, $repo) = @_;

    $data->{gitlab_pipeline} = -e "$repo/.gitlab-ci.yml";
    $data->{jenkins} = -e "$repo/Jenkinsfile";
}

sub analyze_github {
    my ($data, $repo) = @_;

    $data->{travis} = -e "$repo/.travis.yml";
    my @ga = glob("$repo/.github/workflows/*");
    $data->{github_actions} = (scalar(@ga) ? 1 : 0);
    $data->{circleci} = -e "$repo/.circleci";
    $data->{jenkins} = -e "$repo/Jenkinsfile";
    $data->{appveyor} = (-e "$repo/.appveyor.yml") || (-e "$repo/appveyor.yml");
    $data->{azure_pipeline} = -e "$repo/azure-pipelines.yml";
}

sub load_meta_data_of_every_distro {
    my ($self) = @_;

    my @filenames = $self->get_all_meta_filenames;
    my @distros;
    for my $meta_data_file (@filenames) {
        my $data = read_data($meta_data_file);
        my $basename = basename $meta_data_file;
        my $prefix = substr($basename, 0, 2);
        my $metacpan_file = "$self->{data}/metacpan/distributions/$prefix/$basename";
        $data->{metacpan} = read_data($metacpan_file);
        push @distros, $data;
    }
    @distros = sort { $b->{release_date} cmp $a->{release_date} } @distros;

    $self->{distro_to_meta} = {};
    for my $distro (@distros) {
        $self->{distro_to_meta}{$distro->{distribution}} = $distro;
    }
    return @distros;
}

sub get_dependencies {
    my ($self, $distro_name) = @_;

    if ($self->{dependencies}{$distro_name}) {
        return @{$self->{dependencies}{$distro_name}};
    }
    $self->{dependencies}{$distro_name} = []; # avoid recursive call for the same distro

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Get dependencies of $distro_name");

    my %reported;

    my @distributions;
    for my $dep (@{ $self->{immediate_dependencies}{$distro_name} }) {
        next if $dep->{phase} ne 'runtime' or $dep->{relationship} ne 'requires';
        # 'phase' values: runtime, configure, test, develop, build, x_Dist_Zilla
        # 'relationship': requires, recommends, suggests
        my $module = $dep->{module};
        next if $module eq 'perl';
        next if Module::CoreList->first_release($module);

        if (not $self->{module_to_distro}{$module}) {
            if (not $reported{$module}) {
                $logger->warn("Module $module is a dependency, but we could not find which distribution provides it. Is it core?");
                $reported{$module} = 1;
            }
        } else {
            my $new_distro = $self->{module_to_distro}{$module};
        #    # module was utf8
        #    #next if $new_distro eq 'perl';
            push @distributions, $new_distro, $self->get_dependencies($new_distro);
            @distributions = sort {$a cmp $b } uniq @distributions;
        }
    }

    $self->{dependencies}{$distro_name} = \@distributions;
    # $logger->info("Dependencies of '$distro_name': " . Dumper \@distributions);

    return @distributions;
}

sub download_cpants {
    my ($self) = @_;

    return if not $self->{cpants};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Download CPANTS");

    my $folder = catfile($self->{data}, 'cpants');
    make_path $folder;

    $logger->info("Download to '$folder'");

    my $ua = LWP::UserAgent->new(timeout => 5);
    my $json = JSON->new->allow_nonref;

    my @distros = $self->get_all_distribution_filenames;
    my $counter = 0;
    for my $distro_filename (@distros) {
        my $distro =  read_data($distro_filename);

        my $prefix = basename(dirname($distro_filename));
        make_path(catfile($folder, $prefix));
        my $cpants_file = catfile($folder, $prefix, basename($distro_filename));

        my $cpants = read_cpants_file($cpants_file);
        #die Dumper $cpants;
        if (%$cpants) {
            if (not defined $distro->{data}{version}) {
                $logger->error("missing version from distro $distro->{distribution}");
                next;
            }
            if (not defined $cpants->{data}{metadata}{version}) {
                $logger->error("missing version from cpants of $distro->{distribution}"); # . Dumper $cpants);
                next;
            }
            next if $distro->{data}{version} eq $cpants->{data}{metadata}{version};
            $logger->info("distro version_numified: '$distro->{data}{version}' cpants version: '$cpants->{data}{metadata}{version}'");
        }

        #die Dumper $distro;
        my $url = "https://api.cpanauthors.org/v5/release/$distro->{data}{author}/$distro->{distribution}/metadata";
        $logger->info("CPANTS: $url");
        my $response = $ua->get($url);
        my $status_line = $response->status_line;
        if ($status_line eq "200 OK") {
            my $content = $response->decoded_content;
            path($cpants_file)->spew_utf8($content);
        } else {
            $logger->error("CPANTS: $url $status_line " . $response->decoded_content);
            next;
        }

        last if $self->{limit} and ++$counter >= $self->{limit};
    }

    $logger->info("Download CPANTS ended");
}

sub load_dependencies {
    my ($self) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Load dependencies");

    my @distros = $self->get_all_distribution_filenames;
    my %immediate_dependencies;
    my %module_to_distro;
    for my $distro_filename (@distros) {
        my $distro =  read_data($distro_filename);
        # die Dumper $distro->{data}{dependency};
        # [
        #   {
        #     'phase' =>  # build, runtime, configure
        #     'version' => '0',
        #     'relationship' => 'requires',
        #     'module' => 'ExtUtils::MakeMaker'
        #   },
        # ]

        $immediate_dependencies{$distro->{distribution}} = $distro->{data}{dependency};
        for my $module (@{ $distro->{data}{provides} }) {
            if ($module_to_distro{$module}) {
                if ($module_to_distro{$module} eq $distro->{distribution}) {
                    # $logger->warn("Module $module provided twice by $distro->{distribution}");
                    # Date-Simple' is provided twice by 'Date-Simple'
                } else {
                    $logger->error("Module $module provided by two different distributions. Both by '$module_to_distro{$module}' and by '$distro->{distribution}'");
                    # TODO: How will cpanm decide which one to install when the user wants to install the module? The newer release?
                    # Module Datahub::Factory::Importer::VKC provided by two distributions both 'Datahub-Factory-Arthub' and 'Datahub-Factory-VKC'
                }
            }
            $module_to_distro{$module} = $distro->{distribution};
        }
    }
    $self->{immediate_dependencies} = \%immediate_dependencies;
    $self->{module_to_distro} = \%module_to_distro;

    $logger->info("Load dependencies ended");
}

# pre-calculate all the dependencies to update the cache
sub calculate_dependencies {
    my ($self) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Calculate dependencies");
    for my $distribution (keys %{$self->{distro_to_meta}}) {
        $self->get_dependencies($distribution);
    }

    for my $distribution (keys %{$self->{distro_to_meta}}) {
        for my $dependency (@{ $self->{dependencies}{$distribution} }) {
            $self->{reverse_dependency}{$dependency} = [] if not exists $self->{reverse_dependency}{$dependency};
            push @{ $self->{reverse_dependency}{$dependency} }, $distribution;;
        }
    }

    $logger->info("Calculate dependencies ended");
}

sub add_reverse {
    my ($self, $distros) = @_;
    for my $distro (@$distros) {
        $distro->{reverse} = $self->{reverse_dependency}{$distro->{distribution}};
        if (not defined $distro->{reverse}) {
            $distro->{reverse} = [];
        }
        # die Dumper $distro->{reverse};
    }
}

sub distributions_from_modules {
    my ($self, $modules) = @_;
    my %distros;
    for my $module (@$modules) {
        my $name = $self->{module_to_distro}{$module};
        $distros{$name} = 1 if $name;
    }
    return \%distros;
}

sub html {
    my ($self) = @_;

    return if not $self->{html};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Generating HTML pages");

    mkdir $self->{html};
    mkdir "$self->{html}/dist";
    mkdir "$self->{html}/author";
    mkdir "$self->{html}/lists";
    rcopy("static", $self->{html});


    $self->load_authors;

    my @distros = $self->load_meta_data_of_every_distro;
    $self->load_dependencies;
    $self->calculate_dependencies;
    $self->add_reverse(\@distros);
    $self->read_dashboards;

    my $modules_to_be_adopted = $self->get_modules_to_be_adopted;
    $self->{adoption} = $self->distributions_from_modules($modules_to_be_adopted);
    #die Dumper $self->{adoption};

    $self->update_distributions(\@distros);

    $self->html_adoption(\@distros);
    $self->html_top_dependencies(\@distros);
    $self->html_recent(\@distros);
    $self->html_weekly(\@distros);
    $self->html_distributions(\@distros);
    $self->html_authors(\@distros);

    $self->save_page('index.tt', 'index.html', {
    });

    $logger->info("Generating HTML pages ended");
}

sub html_distributions {
    my ($self, $distributions_from_meta_files) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Generating HTML pages for distributions");

    my $counter = 0;
    for my $distribution (@$distributions_from_meta_files) {
        my $distro_name = $distribution->{distribution};
        my $distro_names = $self->{dependencies}{$distro_name};
        my @distros = ($distribution, map { $self->{distro_to_meta}{$_} } @$distro_names);
        my $stats = $self->get_stats(\@distros);
        $self->save_page('distribution.tt', "dist/$distro_name.html", {
            distro => $distribution,
            distros => \@distros,
            stats => $stats,
            title => "$distro_name on CPAN Digger",
        });

        last if $self->{limit} and ++$counter >= $self->{limit};
    }
    $logger->info("Generating HTML pages for distributions ended");
}



sub html_weekly {
    my ($self, $distros) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("HTML weekly");

    $self->save_page('weekly.tt', 'reports.html', {
        report => $self->perlweekly_report,
        title => "Weekly report",
        authors => $self->recent_authors($distros),
    });

    $logger->info("HTML weekly ended");
}

sub html_adoption {
    my ($self, $distributions) = @_;

    my @distros = grep { $self->{adoption}{$_->{distribution}} } @$distributions;
    my $stats = $self->get_stats(\@distros);
    $self->save_page('adoption.tt', 'adoption.html', {
        distros => \@distros,
        stats => $stats,
        title => "Distributions to be adopted",
    });

}

sub html_top_dependencies {
    my ($self, $distributions) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("HTML top dependencies");

    my $count = 0;
    my @top = grep { $count++ < $TOP_DEPENDENCY_PAGE } sort { scalar(@{$b->{reverse}}) <=> scalar(@{$a->{reverse}}) } @$distributions;
    my $stats = $self->get_stats(\@top);
    $self->save_page('river.tt', 'river.html', {
        distros => \@top,
        stats => $stats,
        title => "Most depended on releases on CPAN Digger",
    });
    $logger->info("HTML top dependencies ended");
}


sub html_recent {
    my ($self, $distributions) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("HTML recent");

    my $count = 0;
    my @recent = grep { $count++ < $self->{page} } @$distributions;
    my $stats = $self->get_stats(\@recent);
    $self->save_page('recent.tt', 'recent.html', {
        distros => \@recent,
        stats => $stats,
        title => "Recent releases on CPAN Digger",
    });

    $logger->info("HTML recent ended");
}


sub html_authors {
    my ($self, $distributions) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Generating HTML pages for authors");


    my @authors;
    my @author_ids = sort {$a cmp $b} uniq map { $_->{author} } @$distributions;
    my $counter = 0;
    for my $author_id (@author_ids) {
        $logger->info("Creating HTML page for author $author_id");
        my @filtered = grep { $_->{author} eq $author_id } @$distributions;
        if (@filtered) {
            my $stats = $self->get_stats(\@filtered);
            $self->{authors}{$author_id}{count} = scalar(@filtered);
            my $name = $self->{authors}{$author_id}{data}{name} // '';
            $self->save_page('author.tt', "author/$author_id.html", {
                distros => \@filtered,
                stats => $stats,
                author => $self->{authors}{$author_id},
                title => "$name ($author_id) on CPAN Digger",
            });

            push @authors, $self->{authors}{$author_id};
        }
        last if $self->{limit} and ++$counter >= $self->{limit};
    }

    $self->save_page('authors.tt', 'author/index.html', {
        authors => \@authors,
        title => "List of authors",
    });

    $logger->info("Generating HTML pages for authors ended");
}

sub update_distributions {
    my ($self, $distributions) = @_;

    for my $dist (@$distributions) {
        $dist->{dashboard} = $self->{dashboards}{ $dist->{author} };

        if (not $dist->{vcs_name}) {
            if ($no_vcs_authors{ $dist->{author} }) {
                $dist->{vcs_not_interested} = 1;
            }
        }

        if (not $dist->{has_ci}) {
            if ($no_ci_authors{ $dist->{author} }) {
                $dist->{ci_not_interested} = 1;
            }
            if ($no_ci_distros{ $dist->{distribution} }) {
                $dist->{ci_not_interested} = 1;
            }
        }
    }
}

sub get_stats {
    my ($self, $distros) = @_;

    my %stats = (
        total => scalar @$distros,
        has_vcs => 0,
        vcs => {},
        has_ci => 0,
        ci => {},
        has_bugz => 0,
        bugz => {},
    );

    for my $ci (@ci_names) {
        $stats{ci}{$ci} = 0;
    }

    for my $dist (@$distros) {
        #say Dumper $dist;
        if ($dist->{vcs_vendor}) {
            $stats{has_vcs}++;
            $stats{vcs}{ $dist->{vcs_vendor} }++;
        }

        if ($dist->{issues}) {
            $stats{has_bugz}++;
        }

        if ($dist->{has_ci}) {
            $stats{has_ci}++;
            for my $ci (@ci_names) {
                $stats{ci}{$ci}++ if $dist->{$ci};
            }
        }
    }
    #die Dumper $distros->[0];
    if ($stats{total}) {
        $stats{has_vcs_percentage} = int(100 * $stats{has_vcs} / $stats{total});
        $stats{has_bugz_percentage} = int(100 * $stats{has_bugz} / $stats{total});
        $stats{has_ci_percentage} = int(100 * $stats{has_ci} / $stats{total});
    }

    return \%stats;
}

sub recent_authors {
    my ($self, $distros) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Recent authors");

    my %authors;
    my $max = min(1000, scalar @$distros)-1;
    for my $ix (0..$max) {
        my $author = $distros->[$ix]{author};
        $authors{$author}++;
    }
    my @recent_authors = sort {$b->{count} <=> $a->{count} } map { { id => $_, count => $authors{$_}} }  keys %authors;
    $logger->info("Recent authors ended");
    return \@recent_authors;
}

sub get_modules_to_be_adopted {
    my ($self) = @_;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("get_modules_to_be_adopted");

    my $perm_file = catfile($self->{data}, '06perms.txt');
    if (not -e $perm_file) {
        $logger->warn("Permission file '$perm_file' is missing. Skipping the adoption.");
        return;
    }

    my $pp = PAUSE::Permissions->new(path => $perm_file);
    my $iterator = $pp->module_iterator();

    my @no_owner;
    my @adoptme;
    my @handoff;
    while (my $mp = $iterator->next_module) {
        if (not defined $mp->owner) {
            push @no_owner, $mp->name;
            next;
        }

        if ($mp->owner eq 'ADOPTME' or grep { $_ eq 'ADOPTME' } $mp->co_maintainers) {
            push @adoptme, $mp->name;
            next;
        }

        if ($mp->owner eq 'HANDOFF' or grep { $_ eq 'HANDOFF' } $mp->co_maintainers) {
            push @handoff, $mp->name;
            next;
        }
    }
    return [uniq @adoptme, @handoff];
}

sub perlweekly_report {
    my ($self) = @_;
    # get the number of releases of the previous seven days. Display the start dates, including the name of the day Monday to Sunday. - using MetaCPAN::Client
    # filter to the list of uniquie distributions
    # count the authors
    # count the VCS-es (from meta/ files)
    # count the bugz-es (from meta/ files)
    # count the CI-s (from meta/ files)

    my $dt = $self->{start_time};
    my $days = 7;
    my $end_date       = $dt->ymd;
    my $start_date     = $dt->clone->add( days => -$days )->ymd;

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Start generating perlweekly report");
    #say "$start_date  $end_date";
    my $mcpan = MetaCPAN::Client->new();
    my $rset  = $mcpan->recent(1000);
    my $uploads = 0;
    my %distributions;
    my %authors;
    my $vcs_count = 0;
    my $ci_count = 0;
    my $bugtracker_count = 0;

    while (my $release = $rset->next) {
        #$logger->info("release '$release->{data}{distribution}'");
        #die Dumper $release;
        last if $release->{data}{date} lt $start_date;
        next if $end_date le $release->{data}{date};

        $uploads++;
        $distributions{$release->{data}{distribution}} = 1;
        $authors{ $release->{data}{author} } = 1;

        # load the meta file
        my $distro = lc $release->{data}{distribution};
        my $prefix = substr($distro, 0, 2);
        my $meta_file = catfile($self->{data}, 'meta', $prefix, "$distro.json");
        # say $meta_file;
        my $meta = read_data($meta_file);
        $vcs_count++ if $meta->{vcs_name};
        $ci_count++ if $meta->{has_ci};
        $bugtracker_count++ if $meta->{issues};
    }
    $logger->info("Finished generating perlweekly report");

    return {
        start_date       => $start_date,
        end_date         => $end_date,
        uploads          => $uploads,
        distributions    => scalar(keys %distributions),
        authors          => scalar(keys %authors),
        vcs_count        => $vcs_count,
        ci_count         => $ci_count,
        bugtracker_count => $bugtracker_count,
    };
}

sub save_page {
    my ($self, $template, $file, $params) = @_;

    my %params = %$params;
    $params{version} = $VERSION;
    $params{timestamp} = "$self->{start_time}+00:00";
    $params{title} //= "CPAN Digger";

    my $tt = Template->new({
        INCLUDE_PATH => './templates',
        INTERPOLATE  => 1,
        WRAPPER      => 'wrapper.tt',
    }) or die "$Template::ERROR\n";

    my $html;
    $tt->process($template, \%params, \$html) or die $tt->error(), "\n";
    my $html_file = catfile($self->{html}, $file);
    path($html_file)->spew_utf8($html);
}

sub check_files_on_vcs {
    my ($self) = @_;

    return if not $self->{metavcs};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Starting to check VCS");

    my @meta_filenames = $self->get_all_meta_filenames;
    my $counter = 0;
    for my $meta_file (@meta_filenames) {
        my $meta = read_data($meta_file);
        next if not $meta->{vcs_url};
        my $vcs_folder = catfile($meta->{vcs_folder}, $meta->{vcs_name});
        next if not -e $vcs_folder; # not cloned yet

        $logger->info("folder: $vcs_folder");

        #next if $data->{vcs_last_checked};
        if ($meta->{vcs_vendor} eq 'GitHub') {
            analyze_github($meta, $vcs_folder);
        }
        if ($meta->{vcs_vendor} eq 'GitLab') {
            analyze_gitlab($meta, $vcs_folder);
        }
        if ($meta->{vcs_vendor} eq 'Bitbucket') {
            analyze_bitbucket($meta, $vcs_folder);
        }

        for my $ci (@ci_names) {
            $logger->debug("Is CI '$ci'?");
            if ($meta->{$ci}) {
                $logger->debug("CI '$ci' found!");
                $meta->{has_ci} = 1;
            }
        }

        $meta->{vcs_last_checked} = DateTime->now->strftime("%Y-%m-%dT%H:%M:%S");
        save_data($meta_file, $meta);
    }
}


sub save_data {
    my ($data_file, $data) = @_;
    my $json = JSON->new->allow_nonref;
    path($data_file)->spew_utf8($json->pretty->encode( unbless dclone $data ));
}

sub read_cpants_file {
    my ($data_file) = @_;


    my $data = read_data($data_file);
    return $data if not %$data;

    my $ref = ref $data->{data}{metadata};
    if (not defined $ref or $ref eq '') {
        my $json = JSON->new->allow_nonref;
        $data->{data}{metadata} = $json->decode($data->{data}{metadata});
    }

    return $data;
}

sub read_data {
    my ($data_file) = @_;

    my $json = JSON->new->allow_nonref;
    if (-e $data_file) {
        return $json->decode( path($data_file)->slurp_utf8 );
    }
    return {};
}


42;


=head1 NAME

CPAN::Digger - To dig CPAN

=head1 SYNOPSIS

    cpan-digger

=head1 DESCRIPTION

This is a command line program to collect some meta information about CPAN modules.


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2020 by L<Gabor Szabo|https://szabgab.com/>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.26.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

