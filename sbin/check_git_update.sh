#!/bin/bash

cd /opt/webenabled && git rev-list HEAD...origin/master --count
