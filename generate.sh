#!/usr/bin/bash

perl -Ilib bin/cpan-digger --version

#perl -Ilib bin/cpan-digger --author SZABGAB --vcs --sleep 2
#perl -Ilib bin/cpan-digger --filename lists/demo.txt --vcs --sleep 2
perl -Ilib bin/cpan-digger --recent 200 --vcs --sleep 2

#rm -rf _site/*
mkdir -p _site/
cp -r static/* _site/
perl -Ilib bin/cpan-digger --html _site/

