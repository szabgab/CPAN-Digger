package CPAN::Digger;
use strict;
use warnings FATAL => 'all';

our $VERSION = '1.00';

use Capture::Tiny qw(capture);
use Log::Log4perl ();
use File::Temp qw(tempdir);
use Cwd qw(getcwd);
use Exporter qw(import);
use Data::Dumper qw(Dumper);
use File::Spec ();
use Log::Log4perl ();
use Log::Log4perl::Level ();
use MetaCPAN::Client ();


use CPAN::Digger::DB qw(get_fields);

my $tempdir = tempdir( CLEANUP => 1 );

my %known_licenses = map {$_ => 1} qw(perl_5);


sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    for my $key (keys %args) {
        $self->{$key} = $args{$key};
    }

    $self->{db} = CPAN::Digger::DB->new(db => $self->{db});

    return $self;
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

sub get_data {
    my ($self, $item) = @_;

    my $logger = Log::Log4perl->get_logger();
    my %data = (
        distribution => $item->distribution,
        version      => $item->version,
        author       => $item->author,
    );

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
            if ($self->{github} and $vcs_name eq 'GitHub') {
                analyze_github(\%data);
            }
        }
    } else {
        $logger->warn('No repository for ', $item->distribution);
    }
    return %data;
}


sub analyze_github {
    my ($data) = @_;
    my $logger = Log::Log4perl->get_logger();

    my $vcs_url = $data->{vcs_url};
    my $repo_name = (split '\/', $vcs_url)[-1];
    $logger->info("Analyze GitHub repo '$vcs_url' in directory $repo_name");

    my $git = 'git';

    my @cmd = ($git, "clone", "--depth", "1", $data->{vcs_url});
    my $cwd = getcwd();
    chdir($tempdir);
    my ($out, $err, $exit_code) = capture {
        system(@cmd);
    };
    chdir($cwd);
    my $repo = "$tempdir/$repo_name";

    if ($exit_code != 0) {
        # TODO capture stderr and include in the log
        $logger->error("Failed to clone $vcs_url");
        return;
    }

    $data->{travis} = -e "$repo/.travis.yml";
    $data->{github_actions} = scalar(glob("$repo/.github/workflows/*"));
    $data->{circleci} = -e "$repo/.circleci";
    $data->{appveyor} = (-e "$repo/.appveyor.yml") || (-e "$repo/appveyor.yml");

    for my $ci (qw(travis github_actions circleci appveyor)) {
        if ($data->{$ci}) {
            $data->{has_ci} = 1;
        }
    }
}

sub collect {
    my ($self) = @_;

    my $log_level = $self->{log}; # TODO: shall we validate?
    Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority( $log_level ));
    my $logger = Log::Log4perl->get_logger();
    $logger->info('Starting');
    $logger->info("Recent: $self->{recent}");

    my $mcpan = MetaCPAN::Client->new();
    my $rset;
    if ($self->{author}) {
        my $author = $mcpan->author($self->{author});
        #print $author;
        $rset = $author->releases;
    } else {
        $rset  = $mcpan->recent($self->{recent});
    }
    my %distros;
    my @fields = get_fields();
    while ( my $item = $rset->next ) {
    		next if $distros{ $item->distribution }; # We have already deal with this in this session
            $distros{ $item->distribution } = 1;

            my $row = $self->{db}->db_get_distro($item->distribution);
            next if $row and $row->{version} eq $item->version; # we already have this in the database (shall we call last?)
            my %data = $self->get_data($item);
            #say Dumper %data;
            $self->{db}->db_insert_into(@data{@fields});
            sleep $self->{sleep} if $self->{sleep};
    }

    if ($self->{report}) {
        #print "Text report\n";
        my $distros = $self->{db}->db_get_every_distro();
        for my $distro (@$distros) {
            #die Dumper $distro;
            printf "%-40s %-7s", $distro->{distribution}, ($distro->{vcs_url} ? '' : 'NO VCS');
            if ($self->{github}) {
                printf "%-7s", ($distro->{has_ci} ? '' : 'NO CI');
            }
            print "\n";
        }
    }
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

