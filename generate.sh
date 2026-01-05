#!/bin/bash
set -x

# Just print the version number of the CPAN Digger
perl -Ilib bin/cpan-digger --version

#perl -Ilib bin/cpan-digger --releases
#perl -Ilib bin/cpan-digger --authors

# We fetch that many recent releases, but only take account the ones that are marked as "latest"
# Which is a lot lower than the number we fetched. O(n) as we send one HTTP request for each of the "latest" distributions.
# ~ 1.5 sec for 300 entries (skipped 155)
perl -Ilib bin/cpan-digger --recent 300

# Repository clonings. Time is unrelated to number of projects we report about.
# ~ 1 sec
perl -Ilib bin/cpan-digger --dashboard


# Download a single file from cpan.org
# ~ 7 sec
perl -Ilib bin/cpan-digger --permissions

# ~ 3 min 30 sec for 500
perl -Ilib bin/cpan-digger --cpants --limit 500


# ~ 30 sec for 40,000
perl -Ilib bin/cpan-digger --coverage 40000

# 
perl -Ilib bin/cpan-digger --meta
perl -Ilib bin/cpan-digger --clone 40000 --pull
perl -Ilib bin/cpan-digger --metavcs


mkdir -p _site/
cp -r static/* _site/
perl -Ilib bin/cpan-digger --html _site/
