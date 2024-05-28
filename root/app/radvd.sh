#!/bin/bash

# Check if DEBUG environment variable is set
if [[ -n $RADVD_DEBUG ]]; then
    debug="--debug $RADVD_DEBUG"
else
    debug=""
fi

radvd -p /tmp/radvd.pid --nodaemon $debug
