#!/usr/bin/env bash
# The pr-refine activity check-broker (azure-iac cases 12 and 15): runs with the
# token the broker minted for mutate-tracker in GH_TOKEN and reads the PR once
# with it, so a mint shows as one authenticated read. The write reusable revokes
# the token after this script. Never prints the token.
set -euo pipefail
: "${GH_TOKEN:?}" "${PR_NUMBER:?}" "${GITHUB_REPOSITORY:?}"
number=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq .number)
echo "check-broker: read #${number} with the minted token"
