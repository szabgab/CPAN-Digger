# CPAN Digger

* Collect data from MetaCPAN and GitHub.
* Analyze CPAN modules.
* Find low-hanging fruit to fix on CPAN.

## Several systems in one place

For historcal reasons this repository contains sever systems.

1. The data is collected into an SQLite database on the disk and there is a Mojolicious based web app to display the content. Not in use now.
2. The data is collected into an in-memory SQLite database. A static HTML page is generated. This runs on GitHub Actions and the results are deployed on GitHub pages to [CPAN Digger](https://cpan-digger.perlmaven.com/)
3. In-memory SQLite, the results are printed on STDOUT. This is used weekly to add a new line to the [MetaCPAN report](https://perlweekly.com/metacpan.html)
4. The latest which is in planning phase: Data is collected to json files which are than cached on an S3 storage on Linode and static web pages are generated from the reports using GitHub Actions.

## 1. Usage and development

To collect data from MetaCPAN and GitHub run:

```
perl -I lib bin/cpan-digger
perl -I lib bin/cpan-digger --db cpandigger.db
```

To launch the web application in development mode run:

```
CPAN_DIGGER_DB=cpandigger.db morbo webapp.pl

morbo webapp.pl
```

Then visit http://localhost:3000/

## 2. Currently on GitHub pages

Run this to collect the data and generate the pages just as in GitHub Actons does:

```
./generate.sh
```

or look in the file and run part of the commands.

In order to view this, install

```
cpanm App::HTTPThis
```

and then run

```
http_this _site/
```

## 3. Command line report for the Perl Weekly

See the command here: https://github.com/szabgab/perlweekly/blob/master/bin/metacpan.pl

## 4. Continous collection

* Separate the collection from MetaCPAN and the collection from GitHub.
* Move the data to individual json files (per distribution) to make the data more flexible than SQLite.
* After every run on GitHub Action zip up the data files and upload them to S3 and restore this the next run so we can collect all the data.

## Steps

* Fetch the list of recently uploaded released
* Check if there is a link to VCS
* Check if there is a link to bug tracking system (Q: what if the VCS is GitHub but the bug tracking is RT?)

* If the source code is on GitHub check if some any of the CI system is configured.
* If only .travis.yml exists then report that too as Tracis stopped offering its service.
* Check for license meta field


* Does the documentation contain link to http://search.cpan.org/ ? That is probably some old boyler-plate code and should be either removed or changed
* Is there a link to https://cpanratings.perl.org/ ? I think that site is not maintained any more so probably that link should be removed as well.
* http://www.annocpan.org/ is now something else, that link should be removed for sure
* Is there a link in the docs to http://rt.cpan.org/ while the module actually uses some other bug tracker?

