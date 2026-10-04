#!/usr/bin/env bash
# A read activity must get no token: GH_TOKEN unset, no extraheader in
# .git/config, and a push that fails. Exits with the push's status.
set -uo pipefail

echo "== env"
env | sort

if [[ -n ${GH_TOKEN+x} ]]; then
  echo "== GH_TOKEN is set"
else
  echo "== GH_TOKEN is unset"
fi

echo "== extraheader"
git config --get-regexp '^http\..*\.extraheader$' || echo "no extraheader"

echo "== git push"
GIT_TERMINAL_PROMPT=0 git push origin "HEAD:refs/heads/probe/check-token-$HEAD_SHA"
