#!/bin/sh
dir=`dirname $0`
mtree -e -q -U -p $dir/files <$dir/files.mtree
