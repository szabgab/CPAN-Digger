package CPANDigger;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(get_github_actions get_travis get_vcs);

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

42;
