#!/bin/sh
set -eu
/home/ggul-docker/bin/docker -H unix:///home/ggul-docker/run/docker.sock rm -f sf-optiontrade
echo 'OPTIONTRADE_STOPPED'
