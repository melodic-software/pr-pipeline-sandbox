#!/usr/bin/env bash
# $1 is only the argv token check.sh looks for; $2 is the file it appends to.
while :; do
  date +%s >>"$2"
  sleep 2
done
