#!/usr/bin/env bash
# Probe for claude-code-plugins#12634: does resolveReviewThread work with the
# mutate-branch lane token (contents: write, pull-requests: read)? Resolves the
# one review thread ACTIVITY_ARGS names and prints GitHub's answer verbatim.
set -euo pipefail

if ! [[ ${ACTIVITY_ARGS:-} =~ ^PRRT_[A-Za-z0-9_-]+$ ]]; then
  echo "::error::ACTIVITY_ARGS must be one review thread node id (PRRT_...)"
  exit 1
fi

body=$(jq -cn --arg id "$ACTIVITY_ARGS" \
  '{query: "mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } } }", variables: {id: $id}}')
response="$RUNNER_TEMP/probe-resolve-response.json"
status=$(printf 'Authorization: Bearer %s\n' "$GH_TOKEN" |
  curl -sS -o "$response" -w '%{http_code}' --max-time 30 -X POST -H @- \
    -H 'Content-Type: application/json' --data-binary "$body" "$GITHUB_GRAPHQL_URL") || status=000

echo "probe-resolve-thread: HTTP $status"
jq -r '(.errors // [])[] | "error type=\(.type // "none") message=\(.message)"' "$response" 2>/dev/null || true
jq -c '.data // null' "$response" 2>/dev/null || true
resolved=$(jq -r '(.errors // [] | length) == 0 and .data.resolveReviewThread.thread.isResolved == true' "$response" 2>/dev/null) || resolved=false
rm -f "$response"

[ "$status" = 200 ] && [ "$resolved" = true ] || exit 1
