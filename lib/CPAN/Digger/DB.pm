package CPAN::Digger::DB;
use strict;
use warnings;

use DBI;
use FindBin ();
use Path::Tiny qw(path);
use Exporter qw(import);
use File::HomeDir ();

our @EXPORT_OK = ('get_fields', 'get_db', 'db_insert_into', 'db_get_distro', 'db_get_every_distro');

my $dbh = get_db();
my $sth_get_distro = $dbh->prepare('SELECT * FROM dists WHERE distribution=?');
my $sth_get_every_distro = $dbh->prepare('SELECT * FROM dists');
my @fields = qw(distribution version author vcs_url vcs_name travis github_actions appveyor circleci has_ci);
my $fields = join ', ', @fields;
my $sth_insert = $dbh->prepare("INSERT INTO dists ($fields) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
sub get_fields {
    return @fields;
}

sub get_db {
    # TODO: set the path to the database using env variable or configuration file?
    my $home     = $ENV{CPAN_DIGGER_HOME} || File::HomeDir->my_home;
    my $cpan_digger_dir = File::Spec->catdir($home, '.cpandigger');
    if (not -e $cpan_digger_dir) {
        mkdir $cpan_digger_dir or die "Could not create directory '$cpan_digger_dir' $!";
    }
    my $db_file = File::Spec->catdir($cpan_digger_dir, 'cpandig.db');

    my $exists = -e $db_file;
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_file", "", "", {
        PrintError       => 0,
        RaiseError       => 1,
        AutoCommit       => 1,
        FetchHashKeyName => 'NAME_lc',
    });
    if (not $exists) {
        local $/ = undef;
        my $schema = <DATA>;
        $dbh->do($schema);
    }
    return $dbh
}

sub db_insert_into {
    $sth_insert->execute(@_);
}

sub db_get_distro {
    my ($distribution) = @_;
    $sth_get_distro->execute($distribution);
    my $row = $sth_get_distro->fetchrow_hashref;
    return $row;
}

sub db_get_every_distro {
    $sth_get_every_distro->execute;
    my @distros;
    while (my $row = $sth_get_every_distro->fetchrow_hashref) {
        push @distros, $row;
    }
    return \@distros;
}

42;

__DATA__
CREATE TABLE dists (
    distribution VARCHAR(255) NOT NULL UNIQUE,
    version      VARCHAR(255),
    author       VARCHAR(255),
    vcs_url      VARCHAR(255),
    vcs_name     VARCHAR(255),
    appveyor         BOOLEAN,
    circleci         BOOLEAN,
    travis           BOOLEAN,
    github_actions   BOOLEAN,
    has_ci           BOOLEAN
);
