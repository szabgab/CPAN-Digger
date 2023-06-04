#!/usr/bin/bash

perl -Ilib bin/cpan-digger --version

#perl -Ilib bin/cpan-digger --releases
#perl -Ilib bin/cpan-digger --authors

perl -Ilib bin/cpan-digger --recent 100
perl -Ilib bin/cpan-digger --dashboard
perl -Ilib bin/cpan-digger --coverage 40000
perl -Ilib bin/cpan-digger --meta
perl -Ilib bin/cpan-digger --clone 40000 --pull
perl -Ilib bin/cpan-digger --metavcs


mkdir -p _site/
cp -r static/* _site/
perl -Ilib bin/cpan-digger --html _site/
