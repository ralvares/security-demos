#!/bin/sh

set -e

exec java "$@" -jar /app/cve-2017-538-example.jar
