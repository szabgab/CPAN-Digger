use Mojolicious::Lite -signatures;

use FindBin ();
use DateTime;
use Template;

use lib "$FindBin::Bin/lib";
use CPAN::Digger::DB qw(db_get_every_distro db_get_distro);


get '/' => sub ($c) {
    my $distros = db_get_every_distro();


    my %data = (
        timestamp     => DateTime->now,
        distributions => $distros,
    );

    $c->render(template => 'index',
        distributions => $distros,
        );
};

get '/dist/:dist' => sub ($c) {
    my $distribution = $c->stash('dist');;
    my $distro = db_get_distro($distribution);
    $c->render(template => 'distribution',
        distribution => $distribution,
        dist => $distro,
    );
};

app->start;
