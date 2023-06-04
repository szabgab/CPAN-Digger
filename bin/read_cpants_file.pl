use strict;
use warnings;
use feature 'say';

use Data::Dumper qw(Dumper);
use Path::Tiny qw(path);
use JSON ();

my $file = shift @ARGV or die "Usage: $0 FILENAME";

my $json = JSON->new->allow_nonref;
my $all = $json->decode( path($file)->slurp_utf8 );
#say Dumper [keys %{ $all->{data} }];
my $ref = ref $all->{data}{metadata};
#say defined $ref;
#say $ref;
my $metadata;
if (defined $ref and $ref eq 'HASH') {
    $metadata = $all->{data}{metadata};
} else {
    $metadata = $json->decode($all->{data}{metadata});
}
#say Dumper [keys %{ $metadata }];
say Dumper $metadata;

