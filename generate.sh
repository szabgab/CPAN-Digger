#!/bin/bash
set -x

# Just print the version number of the CPAN Digger
time perl -Ilib bin/cpan-digger --version

#perl -Ilib bin/cpan-digger --releases
#perl -Ilib bin/cpan-digger --authors

# We fetch that many recent releases, but only take account the ones that are marked as "latest"
# Which is a lot lower than the number we fetched. O(n) as we send one HTTP request for each of the "latest" distributions.
# ~ 1.5 sec for 300 entries (skipped 155)
# ~ 1.8 sec for 500 entries (skipped 270)
time perl -Ilib bin/cpan-digger --recent 500

# Repository clonings. Time is unrelated to number of projects we report about.
# ~ 1 sec
time perl -Ilib bin/cpan-digger --dashboard


# Download a single file from cpan.org
# ~ 7 sec
time perl -Ilib bin/cpan-digger --permissions

# ~ 3.5 min for 500
time perl -Ilib bin/cpan-digger --cpants --limit 500


# ~ 30 sec for 40,000
time perl -Ilib bin/cpan-digger --coverage 40000

# 0.5 sec
time perl -Ilib bin/cpan-digger --meta

# Clone the repositories of the distribution we have up to a max of 40000 distros.
# The actual number is impaceted by the number of "latest" distributions we got in the "--recent" request above.
# Was (38 sec) when using full clone
# ~22 sec now that we have shallow clone
time perl -Ilib bin/cpan-digger --clone 40000 --pull


# ~ 0.4 sec
time perl -Ilib bin/cpan-digger --metavcs


# ~ 6 sec
mkdir -p _site/
cp -r static/* _site/
time perl -Ilib bin/cpan-digger --html _site/
