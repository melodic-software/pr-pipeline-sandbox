#!/usr/bin/env bash
set -euo pipefail
: "${GH_TOKEN:?}" "${PR_NUMBER:?}" "${GITHUB_REPOSITORY:?}"
number=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq .number)
echo "check-broker: read #${number} with the minted token"
