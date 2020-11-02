use strict;
use warnings;

use ExtUtils::MakeMaker;
WriteMakefile(
    NAME          => 'CPAN::Digger',
    AUTHOR        => 'Gabor Szabo <gabor@szabgab.com>',
    VERSION_FROM  => 'lib/CPAN/Digger.pm',
    ABSTRACT_FROM => 'lib/CPAN/Digger.pm',
    LICENSE       => 'perl',
    EXE_FILES     => ['bin/cpan-digger'],
    dist          => { COMPRESS => 'gzip', SUFFIX => 'gz' },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/szabgab/CPAN-Digger.git',
                web  => 'https://github.com/szabgab/CPAN-Digger',
            },
            bugtracker => {web => 'https://github.com/szabgab/CPAN-Digger/issues'},
            homepage   => 'https://perlmaven.com/cpan-digger',
        },
    },
);
