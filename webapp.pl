use Mojolicious::Lite -signatures;

#use File::Spec ();
use FindBin ();
use DateTime;
use Template;

use lib "$FindBin::Bin/lib";
use CPANDigger::DB qw(db_get_every_distro);


get '/' => sub ($c) {
    my $distros = db_get_every_distro();


    my %data = (
        timestamp     => DateTime->now,
        distributions => $distros,
    );

    my $tt = Template->new({
        INCLUDE_PATH => File::Spec->catdir($FindBin::Bin, 'templates'),
        INTERPOLATE  => 1,
    }) or die "$Template::ERROR\n";

    my $html;
    $tt->process('main.tt', \%data, \$html) or die $tt->error(), "\n";


    $c->render(text => $html);
};


app->start;