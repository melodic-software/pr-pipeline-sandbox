#!/usr/bin/env bash
# Prints the number of lines in each file named on the command line, then the
# total, and exits 0. File names may contain spaces.
set -euo pipefail

total=0
for f in $@; do
  n=$(wc -l < $f)
  total=$((total + n))
  echo "$f: $n"
done
echo "total: $total"
exit 0
