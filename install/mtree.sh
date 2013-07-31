#!/bin/sh
dir=`dirname $0`
mtree -k mode -n  -c -p $dir/files
