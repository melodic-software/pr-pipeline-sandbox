#!/usr/bin/env bash
set -uo pipefail

failed=0

for name in ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN GH_TOKEN GITHUB_TOKEN; do
  if [[ -n ${!name+x} ]]; then
    echo "FAIL: $name is set"
    failed=1
  else
    echo "ok: $name is unset"
  fi
done

echo "== token-like variable names"
env | cut -d= -f1 | grep -iE 'token|secret|key|private|oidc' | sort || echo "(none)"

if git config --get-regexp '^http\..*\.extraheader$' >/dev/null; then
  echo "FAIL: .git/config holds an extraheader"
  failed=1
else
  echo "ok: no extraheader"
fi

if GIT_TERMINAL_PROMPT=0 git push origin "HEAD:refs/heads/probe/check-read-token-$HEAD_SHA"; then
  echo "FAIL: git push succeeded"
  failed=1
else
  echo "ok: git push failed"
fi

exit "$failed"
