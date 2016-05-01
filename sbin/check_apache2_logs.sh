#!/bin/bash

# there should be more than a single log file
zgrep -c $1 /home/clients/websites/*/logs/*-access_log*|awk -F':' '{s+=$2} END {print s}'
