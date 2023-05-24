perl -Ilib bin/cpan-digger --version
cp -r static _site
mkdir _site/lists
perl -Ilib bin/cpan-digger --author SZABGAB --vcs --sleep 2 --html _site/szabgab
perl -Ilib bin/cpan-digger --filename lists/demo.txt --vcs --sleep 2 --html _site/lists/demo
perl -Ilib bin/cpan-digger --recent 200 --vcs --sleep 2 --html _site/recent

