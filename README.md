# The new CPAN Digger

* Find low-hanging fruit to fix in CPAN

## Usage and development

To collect data from MetaCPAN and GitHub run:

```
perl -I lib bin/cpan-digger
```

To launch the web application in development mode run:

```
morbo webapp.pl
```

Then visit http://localhost:3000/

## Steps

* Fetch the list of recently uploaded released
* Check if there is a link to VCS
* Check if there is a link to bug tracking system (Q: what if the VCS is GitHub but the bug tracking is RT?)

* If the source code is on GitHub check if .travis.yml exists
* Maybe: Check if Travis is indeed running on this project

* Check for other CI systems?
* Check for license meta field


* Does the documentation contain link to http://search.cpan.org/ ? That is probably some old boler-plate code and should be either removed or changed
* Is there a link to https://cpanratings.perl.org/ ? I think that site is not maintained any more so probably that link should be removed as well.
* http://www.annocpan.org/ is now something else, that link should be removed for sure
* Is there a link in the docs to http://rt.cpan.org/ while the module actually uses some other bug tracker?

