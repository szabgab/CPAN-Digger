use strict;
use warnings;
use Test::More;


unless ( $ENV{RELEASE_TESTING} ) {
    plan( skip_all => "Author tests not required for installation." );
}

use Test::Version 1.001001 qw( version_all_ok ), {
    is_strict   => 0,
    has_version => 1,
    consistent  => 1,
  };

# test blib or lib by default
version_all_ok();

done_testing;
