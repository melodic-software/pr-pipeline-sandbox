#!/usr/bin/env bash
# Prints the first word of each line read from standard input, one per line.
# Blank lines print nothing.
set -euo pipefail

while read -r line; do
  echo "${line%% *}"
done
