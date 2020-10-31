package CPANDigger::DB;
use strict;
use warnings;

use DBI;
use FindBin ();
use Path::Tiny qw(path);
use Exporter qw(import);

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
