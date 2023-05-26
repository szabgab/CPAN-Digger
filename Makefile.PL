use strict;
use warnings;

use ExtUtils::MakeMaker;
WriteMakefile(
    NAME          => 'CPAN::Digger',
    AUTHOR        => 'Gabor Szabo <gabor@szabgab.com>',
    VERSION       => '1.00',
    ABSTRACT      => 'CPAN Digger',
    LICENSE       => 'perl',
    EXE_FILES     => ['bin/cpan-digger'],
    dist          => { COMPRESS => 'gzip', SUFFIX => 'gz' },
    PREREQ_PM => {
        'Capture::Tiny'    => 0,
        'Data::Structure::Util' => 0,
        'DateTime'         => 0,
        'DateTime::Format::ISO8601' => 0,
        'File::Copy::Recursive' => 0,
        'JSON'             => 0,
        'List::MoreUtils'  => 0,
        'Log::Log4perl'    => 0,
        'LWP::UserAgent'   => 0,
        'MetaCPAN::Client' => 2.026,
        'Path::Tiny'       => 0,
        'Template'         => 0,
    },
    TEST_REQUIRES => {
        'Test::More'    => 0,
        'Mock::Quick'   => 0,
        'Storable'      => 0,
    },
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
