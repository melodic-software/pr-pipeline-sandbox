#!/usr/bin/env bash
# Prints the largest of the integers given as arguments. Exits 2 with no
# arguments.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: max-of.sh N..." >&2
  exit 2
fi

max=$1
for n in "$@"; do
  if [ "$n" -lt "$max" ]; then
    max=$n
  fi
done
echo "$max"
