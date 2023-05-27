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
use Exporter qw(import);
use File::Copy::Recursive qw(rcopy);
use File::Spec::Functions qw(catfile);
use File::Basename qw(basename);
use File::Temp qw(tempdir);
use JSON ();
use List::MoreUtils qw(uniq);
use Log::Log4perl ();
use LWP::UserAgent ();
use MetaCPAN::Client ();
use Path::Tiny qw(path);
use Storable qw(dclone);
use Template ();

my $git = 'git';
my $root = getcwd();

my @ci_names = qw(travis github_actions circleci appveyor azure_pipeline gitlab_pipeline bitbucket_pipeline jenkins);

# Authors who indicated (usually in an email exchange with Gabor) that they don't have public VCS and are not
# interested in adding one. So there is no point in reporting their distributions.
my %no_vcs_authors = map { $_ => 1 } qw(PEVANS NLNETLABS RATCLIFFE JPIERCE GWYN JOHNH LSTEVENS GUS KOBOLDWIZ STRZELEC TURNERJW MIKEM MLEHMANN);

# Authors that are not interested in CI for all (or at least for some) of their modules
my %no_ci_authors = map { $_ => 1 } qw(SISYPHUS GENE PERLANCAR);

my %no_ci_distros = map { $_ => 1 } qw(Kelp-Module-Sereal);


my $tempdir = tempdir( CLEANUP => ($ENV{KEEP_TEMPDIR} ? 0 : 1) );

my %known_licenses = map {$_ => 1} qw(agpl_3 apache_2_0 artistic_2 bsd mit gpl_2 gpl_3 lgpl_2_1 lgpl_3_0 perl_5); # open_source, unknown

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    for my $key (keys %args) {
        $self->{$key} = $args{$key};
    }
    $self->{log} = uc $self->{log};
    $self->{clone_vcs} = delete $self->{clone};
    $self->{total} = 0;

    my $dt = DateTime->now;
    $self->{start_time} = $dt;
    $self->{end_date}       = $dt->ymd;
    if ($self->{days}) {
        $self->{start_date}     = $dt->add( days => -$self->{days} )->ymd;
    }
    $self->{data} = $args{data}; # data folder where we store the json files
    mkdir "logs";
    mkdir "repos";
    mkdir $self->{data};
    mkdir "$self->{data}/meta";
    mkdir "$self->{data}/metacpan";
    mkdir "$self->{data}/metacpan/distributions";
    mkdir "$self->{data}/metacpan/authors";
    mkdir "$self->{data}/metacpan/coverage";

    return $self;
}

sub run {
    my ($self) = @_;


    $self->setup_logger($self->{start_time});
    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info('CPAN::Digger started');

    $self->download_authors_from_metacpan;

    my $rset = $self->search_releases_on_metacpan;
    $self->get_release_data_from_metacpan($rset);

    $self->get_coverage_data;
    $self->update_meta_data_from_releases;

    $self->clone_vcs;
    #$self->check_files_on_vcs;

    #$self->stdout_report;
    #$self->html;

    my $end = DateTime->now;
    my ($minutes, $seconds) = ($end-$self->{start_time})->in_units('minutes', 'seconds');
    $logger->info("CPAN:Digger ended. Elapsed time: $minutes minutes $seconds seconds");
}

sub setup_logger {
    my ($self, $start) = @_;

    my $log_level = $self->{log}; # TODO: shall we validate?
    my $logfile = $start->strftime("%Y-%m-%d-%H-%M-%S");

    my $conf = qq(
      log4perl.category.digger           = $log_level, Logfile
      log4perl.appender.Logfile          = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.filename = logs/digger-$logfile.log
      log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Logfile.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss} [%r] %F %L %p %m%n
    );

    Log::Log4perl::init( \$conf );

}

sub download_authors_from_metacpan {
    my ($self) = @_;

    return if not $self->{authors};

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
    $logger->info("Author: $self->{author}") if $self->{author};
    $logger->info("Filename $self->{filename}") if $self->{filename};
    $logger->info("Distribution $self->{distro}") if $self->{distro};
    $logger->info("All the releases") if $self->{releases};

    my $mcpan = MetaCPAN::Client->new();
    my $rset;
    if ($self->{author}) {
        my $author = $mcpan->author($self->{author});
        #say $author;
        $rset = $author->releases;
    } elsif ($self->{filename}) {
        open my $fh, '<', $self->{filename} or die "Could not open '$self->{filename}' $!";
        my @releases = <$fh>;
        chomp @releases;
        my @either = map { { distribution =>  $_ } } @releases;
        $rset = $mcpan->release( {
            either => \@either
        });
    } elsif ($self->{distro}) {
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
    $logger->info("Process data from metacpan");

    my $mcpan = MetaCPAN::Client->new();

    while ( my $release = $rset->next ) {
        next if $release->{data}{status} ne 'latest';
        #$logger->info("Release: " . $release->name);
        #$logger->info("Distribution: " . $release->distribution);
        my $distribution =  lc $release->distribution;
        my $prefix = substr($distribution, 0, 2);
        mkdir catfile($self->{data}, 'metacpan', 'distributions', $prefix);
        my $data_file = catfile($self->{data}, 'metacpan', 'distributions', $prefix, "$distribution.json");
        $logger->info("data file $data_file");
        save_data($data_file, $release);
    }
}

sub read_dir {
    my ($dir) = @_;

    opendir(my $dh, $dir) or die "Could not open directory $dir. $!";
    my @entries = grep { $_ ne '.' and $_ ne '..' } readdir $dh;
    closedir $dh;
    return @entries;
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

    my @distribution_filenames = $self->get_all_distribution_filenames;
    my $counter = 0;
    for my $distribution_file (@distribution_filenames) {
        my $distribution_data = read_data($distribution_file);
        my $prefix = substr(basename($distribution_file), 0, 2);
        mkdir catfile($self->{data}, 'meta', $prefix);
        my $meta_filename = catfile($self->{data}, 'meta', $prefix, basename($distribution_file));
        $logger->info("distribution $distribution_file => $meta_filename");
        my %meta;
        my $distribution = $distribution_data->{distribution};
        $logger->debug("distribution: $distribution");
        my $repository = $distribution_data->{data}{resources}{repository};
        if ($repository) {
            my ($real_repo_url, $folder, $name, $vendor) = get_vcs($repository);
            if ($vendor) {
                $meta{repo_url} = $real_repo_url;
                $meta{repo_folder} = $folder;
                $meta{repo_name} = $name;
                $meta{repo_vendor} = $vendor;
                $logger->info("VCS: $vendor $real_repo_url");
            }
        } else {
            $logger->error("distribution $distribution has no repository");
        }
        save_data($meta_filename, \%meta);
    }

    #$logger->debug('      ', $release->author);
    #$data->{version}      = $release->version;
    #$data->{author}       = $release->author;
    #$data->{date}         = $release->date;

    #my @licenses = @{ $release->license };
    #$data->{licenses} = join ' ', @licenses;
    #$logger->debug('      ',  $data->{licenses});
    #for my $license (@licenses) {
    #    if ($license eq 'unknown') {
    #        $logger->error("Unknown license '$license' for $data->{distribution}");
    #    } elsif (not exists $known_licenses{$license}) {
    #        $logger->warn("Unknown license '$license' for $data->{distribution}. Probably CPAN::Digger needs to be updated");
    #    }
    #}
    # if there are not licenses =>
    # if there is a license called "unknonws"
    # check against a known list of licenses (grow it later, or look it up somewhere?)
    #my %resources = %{ $release->resources };
    ##say '  ', join ' ', keys %resources;
    #$self->get_bugtracker(\%resources, $data);

    #$data->{vcs_last_checked} = 0;

    #    next if $release->date lt $self->{start_date};
    #    next if $self->{end_date} le $release->date;
    #}

    ## $logger->info("status: $release->{data}{status}");
    ## There are releases where the status is 'cpan'. They can be in the recent if for example they dev releases
    ## with a _ in their version number such as Astro-SpaceTrack-0.161_01
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
}

sub clone_vcs {
    my ($self) = @_;

    return if not $self->{clone_vcs};

    my $logger = Log::Log4perl->get_logger('digger');
    $logger->info("Clone VCSes");

    my @distribution_filenames = $self->get_all_distribution_filenames;
    my $counter = 0;
    for my $distribution_file (@distribution_filenames) {
        my $distribution_data = read_data($distribution_file);

        #my $repo_is_accessible = check_repo($real_repo_url);
        #if ($repo_is_accessible) {
        #    $self->clone_one_vcs($real_repo_url, $folder, $name);
        #}

        last if ++$counter >= $self->{clone_vcs};
    }
}

sub clone_one_vcs {
    my ($self, $git_url, $folder, $name) = @_;

    my $logger = Log::Log4perl::get_logger("digger");
    $logger->info("Cloning $git_url to $folder");

    chdir($folder);
    my @cmd;
    if (-e $name) {
        chdir($name);
        # TODO: check if the git_url is the same as our remote or if it has moved; we can update the remote easily
        @cmd = ($git, "pull");
    } else {
        @cmd = ($git, "clone", $git_url);
    }
    $logger->info(join(" ", @cmd));
    my ($out, $err, $exit_code) = capture {
        system(@cmd);
    };
    chdir($root);
    if ($exit_code) {
        $logger->error("exit code: $exit_code");
        $logger->error("stdout: $out");
        $logger->error("stderr: $err");
        return;
    }

    return 1;
}


sub read_dashboards {
    my ($self) = @_;
    my $path = 'dashboard';
    $self->{dashboards} = { map { substr(basename($_), 0, -5) => 1 } glob "$path/authors/*.json" };
}

sub get_vcs {
    my ($repository) = @_;

    my $logger = Log::Log4perl->get_logger('digger');

    return if not $repository;

    # Try to get the web link
    my $url = $repository->{web};
    if (not $url) {
        $url = $repository->{url};
        if (not $url) {
            $logger->error("No URL found");
            return;
        }
    }

    $url = lc $url;
    $url =~ s{^git://}{https://};
    $url =~ s{^http://}{https://};
    $url =~ s{\.git$}{};

    my $vendor = "repository";
    my $git_url;
    if ($url =~ m{https://(github\.com|gitlab\.com|bitbucket\.org)/([a-zA-Z0-9-]+)/([a-zA-Z0-9_-]+)}) {
        my $vendor_host = $1;
        my $owner = $2;
        my $name = $3;
        $vendor = substr($vendor_host, 0, -4);
        $git_url = "https://$vendor_host/$owner/$name";
        my $folder = catfile('repos', $vendor, $owner);
        mkdir catfile('repos', $vendor);
        mkdir $folder;
        return $git_url, $folder, $name, $vendor;
    }

    $logger->error("Unrecognized vendor for $url");
    return;
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
    my ($vcs_url) = @_;

    my $logger = Log::Log4perl->get_logger('digger');

    my $ua = LWP::UserAgent->new(timeout => 5);
    my $response = $ua->get($vcs_url);
    my $status_line = $response->status_line;
    if ($status_line eq '404 Not Found') {
        $logger->error("Repository '$vcs_url' Received 404 Not Found. Please update the link in the META file");
        return;
    }
    if ($response->code != 200) {
        $logger->error("Repository '$vcs_url'  got a response of '$status_line'. Please report this to the maintainer of CPAN::Digger.");
        return;
    }
    if ($response->redirects) {
        $logger->error("Repository '$vcs_url' is being redirected. Please update the link in the META file");
        return;
    }

    return 1;
}



sub analyze_vcs {
    my ($data) = @_;
    my $logger = Log::Log4perl->get_logger('digger');

    my $vcs_url = $data->{vcs_url};
    my $repo_name = (split '\/', $vcs_url)[-1];
    $logger->info("Analyze repo '$vcs_url' in directory $repo_name");

    my $git = 'git';

    my @cmd = ($git, "clone", "--depth", "1", $data->{vcs_url});
    my $cwd = getcwd();
    chdir($tempdir);
    my ($out, $err, $exit_code) = capture {
        system(@cmd);
    };
    chdir($cwd);
    my $repo = "$tempdir/$repo_name";
    $logger->debug("REPO path '$repo'");

    if ($exit_code != 0) {
        # TODO capture stderr and include in the log
        $logger->error("Failed to clone $vcs_url");
        return;
    }

    if ($data->{vcs_name} eq 'GitHub') {
        analyze_github($data, $repo);
    }
    if ($data->{vcs_name} eq 'GitLab') {
        analyze_gitlab($data, $repo);
    }
    if ($data->{vcs_name} eq 'Bitbucket') {
        analyze_bitbucket($data, $repo);
    }


    for my $ci (@ci_names) {
        $logger->debug("Is CI '$ci'?");
        if ($data->{$ci}) {
            $logger->debug("CI '$ci' found!");
            $data->{has_ci} = 1;
        }
    }
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

sub get_every_distro {
    my ($self) = @_;

    my @distros;
    my $dir = path($self->{data});
    for my $data_file ( $dir->children ) {
        my $data = read_data($data_file);
        push @distros, $data;
    }
    @distros = sort { $b->{date} cmp $a->{date} } @distros;
    return \@distros;
}


sub html {
    my ($self) = @_;

    return if not $self->{html};
    mkdir $self->{html};
    mkdir "$self->{html}/author";
    mkdir "$self->{html}/lists";
    rcopy("static", $self->{html});

    $self->read_dashboards;

    my @distros = @{ $self->get_every_distro };
    my $count = 0;
    my @recent = grep { $count++ < 50 } @distros;
    $self->html_report('recent.html', \@recent);

    my @authors = sort {$a cmp $b} uniq map { $_->{author} } @distros;
    for my $author (@authors) {
        my @filtered = grep { $_->{author} eq $author } @distros;
        $self->html_report("author/$author.html", \@filtered);
    }

    $self->save_page('authors.tt', 'author/index.html', {
        version => $VERSION,
        timestamp => DateTime->now,
        authors => \@authors,
    });

    $self->save_page('index.tt', 'index.html', {
        version => $VERSION,
        timestamp => DateTime->now,
    });
}

sub html_report {
    my ($self, $page, $distros) = @_;

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
        $dist->{dashboard} = $self->{dashboards}{ $dist->{author} };
        if ($dist->{vcs_name}) {
            $stats{has_vcs}++;
            $stats{vcs}{ $dist->{vcs_name} }++;
        } else {
            if ($no_vcs_authors{ $dist->{author} }) {
                $dist->{vcs_not_interested} = 1;
            }
        }
        if ($dist->{issues}) {
            $stats{has_bugz}++;
        }
        if ($dist->{has_ci}) {
            $stats{has_ci}++;
            for my $ci (@ci_names) {
                $stats{ci}{$ci}++ if $dist->{$ci};
            }
        } else {
            if ($no_ci_authors{ $dist->{author} }) {
                $dist->{ci_not_interested} = 1;
            }
            if ($no_ci_distros{ $dist->{distribution} }) {
                $dist->{ci_not_interested} = 1;
            }
        }
    }
    if ($stats{total}) {
        $stats{has_vcs_percentage} = int(100 * $stats{has_vcs} / $stats{total});
        $stats{has_bugz_percentage} = int(100 * $stats{has_bugz} / $stats{total});
        $stats{has_ci_percentage} = int(100 * $stats{has_ci} / $stats{total});
    }

    $self->save_page('main.tt', $page, {
        distros => $distros,
        version => $VERSION,
        timestamp => DateTime->now,
        stats => \%stats,
    });

}

sub save_page {
    my ($self, $template, $file, $params) = @_;

    my $tt = Template->new({
        INCLUDE_PATH => './templates',
        INTERPOLATE  => 1,
        WRAPPER      => 'wrapper.tt',
    }) or die "$Template::ERROR\n";

    my $html;
    $tt->process($template, $params, \$html) or die $tt->error(), "\n";
    my $html_file = catfile($self->{html}, $file);
    open(my $fh, '>', $html_file) or die "Could not open '$html_file'";
    print $fh $html;
    close $fh;
}


sub check_files_on_vcs {
    my ($self) = @_;

    return if not $self->{check_vcs};

    my $logger = Log::Log4perl->get_logger('digger');

    $logger->info("Starting to check GitHub");
    $logger->info("Tempdir: $tempdir");

    my $dir = path($self->{data});
    for my $data_file ( $dir->children ) {
        $logger->info("$data_file");
        my $data = read_data($data_file);
        $logger->info("vcs_name: " . ($data->{vcs_name} // "MISSING"));

        next if not $data->{vcs_name};
        next if $data->{vcs_last_checked};

        analyze_vcs($data);
        $data->{vcs_last_checked} = DateTime->now->strftime("%Y-%m-%dT%H:%M:%S");
        save_data($data_file, $data);

        sleep $self->{sleep} if $self->{sleep};
    }
}


sub stdout_report {
    my ($self) = @_;

    return if not $self->{report};

    print "Report\n";
    print "------------\n";
    my @distros = @{ $self->get_every_distro };
    if ($self->{limit} and @distros > $self->{limit}) {
        @distros = @distros[0 .. $self->{limit}-1];
    }
    for my $distro (@distros) {
        #die Dumper $distro;
        printf "%s %-40s %-7s", $distro->{date}, $distro->{distribution}, ($distro->{vcs_url} ? '' : 'NO VCS');
        if ($self->{check_vcs}) {
            printf "%-7s", ($distro->{has_ci} ? '' : 'NO CI');
        }
        print "\n";
    }

    if ($self->{days}) {
        my ($distro_count, $authors, $vcs_count, $ci_count, $bugtracker_count) = count_unique(\@distros, $self->{start_date}, $self->{end_date});
        printf
            "Last week there were a total of %s uploads to CPAN of %s distinct distributions by %s different authors. Number of distributions with link to VCS: %s. Number of distros with CI: %s. Number of distros with bugtracker: %s.\n",
            $self->{total}, $distro_count, $authors, $vcs_count,
            $ci_count, $bugtracker_count;
        print " $self->{total}; $distro_count; $authors; $vcs_count; $ci_count; $bugtracker_count;\n";
    }
}

sub count_unique {
    my ($distros, $start_date, $end_date) = @_;
    my $logger = Log::Log4perl->get_logger('digger');

    my $unique_distro = 0;
    my %authors; # number of different authors in the given time period
    my $vcs_count = 0;
    my $ci_count = 0;
    my $bugtracker_count = 0;

    for my $distro (@$distros) {
        $logger->info("$distro->{author} $distro->{distribution} $distro->{date}");
        next if defined($start_date) and $start_date gt $distro->{date};
        next if defined($end_date) and $end_date lt $distro->{date};

        $unique_distro++;
        $authors{ $distro->{author} } = 1;
        $vcs_count++ if $distro->{vcs_name};
        $ci_count++ if $distro->{has_ci};
        $bugtracker_count++ if $distro->{issues};
    }
    return $unique_distro, scalar(keys %authors), $vcs_count, $ci_count, $bugtracker_count;
}

sub save_data {
    my ($data_file, $data) = @_;
    my $json = JSON->new->allow_nonref;
    path($data_file)->spew_utf8($json->pretty->encode( unbless dclone $data ));
}

sub read_data {
    my ($data_file) = @_;

    my $json = JSON->new->allow_nonref;
    if (-e $data_file) {
        open my $fh, '<:encoding(utf8)', $data_file or die $!;
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

