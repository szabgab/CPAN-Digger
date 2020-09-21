package CPANDigger;
use strict;
use warnings;

use Log::Log4perl ();
use LWP::UserAgent;
use Exporter qw(import);

our @EXPORT_OK = qw(get_github_actions get_travis get_circleci get_vcs get_data);

sub get_github_actions {
    my ($url) = @_;
    return _check_url(qq{$url/tree/master/.github/workflows});
}

sub get_circleci {
    my ($url) = @_;
    return _check_url(qq{$url/tree/master/.circleci});
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

sub get_data {
    my ($item) = @_;
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
            if ($vcs_name eq 'GitHub') {
                $data{travis} = get_travis($vcs_url);
                if ($data{travis}) {
                    $data{has_ci} = 1;
                }
                if (not $data{has_ci}) {
                    $data{github_actions} = get_github_actions($vcs_url);
                    if ($data{github_actions}) {
                        $data{has_ci} = 1;
                    }
                }
                if (not $data{has_ci}) {
                    $data{circleci} = get_circleci($vcs_url);
                }
            }
        }
    } else {
        $logger->warn('No repository for ', $item->distribution);
    }
    return %data;
}

42;
