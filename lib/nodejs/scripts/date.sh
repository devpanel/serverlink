#!/bin/bash
echo "Date: $(date)"
echo "(stderr)" 1>&2
echo "(stdout) 1->  $1  2->  $2  3->  $3"
echo "Running: $0 $@"