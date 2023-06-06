#!/usr/bin/bash

cmd="$*"
if [ "$cmd" == "" ]
then
    cmd=./generate.sh
fi
#echo $cmd

name="cpan-digger-$(date +%s)"
#echo $name


docker build -t cpan-digger .
docker run     --rm -w /opt -v$(pwd):/opt --name $name --user ubuntu cpan-digger $cmd
# docker run -it --rm -w /opt -v$(pwd):/opt --name cpan-digger --user ubuntu cpan-digger bash
