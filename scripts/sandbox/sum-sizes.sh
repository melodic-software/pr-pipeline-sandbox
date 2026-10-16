#!/usr/bin/env bash
# Usage: sum-sizes.sh DIR [bytes|kb]
# Prints the total size of the regular files directly in DIR, in bytes by
# default or in whole kilobytes (1024 bytes) with `kb`. Exits 2 when DIR is
# missing or is not a directory.
set -euo pipefail

dir=${1:-}
mode=${2:-bytes}

if [ -z "$dir" ]; then
  echo "usage: sum-sizes.sh DIR [bytes|kb]" >&2
fi
if [ ! -d "$dir" ]; then
  echo "not a directory: $dir" >&2
  exit 1
fi

total=0
for f in "$dir"/*; do
  [ -f "$f" ] || continue
  size=$(stat -c %s "$f")
  total=$((total + size))
done

if [[ $mode == kb ]]; then
  echo $((total / 1000))
else
  echo "$total"
fi
