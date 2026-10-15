#!/usr/bin/env bash
# PROBE, remove after: does the lane token this activity's effect mints let
# the lanes App enqueue a PR (enqueuePullRequest) and enable auto-merge
# (enablePullRequestAutoMerge)? Prints each GraphQL response, then always
# dequeues and disables auto-merge. Exits 0 whatever the probe answers.
#
# Environment: GH_TOKEN (lane token), GITHUB_REPOSITORY, PR_NUMBER, HEAD_SHA.
set -uo pipefail

: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${PR_NUMBER:?}" "${HEAD_SHA:?}"
[[ $PR_NUMBER =~ ^[1-9][0-9]*$ && $HEAD_SHA =~ ^[0-9a-f]{40}$ ]] || {
  echo "::error::malformed PR_NUMBER or HEAD_SHA"
  exit 1
}

id=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq .node_id) || exit 1

call() {
  echo "== $1"
  gh api graphql -f query="$2" -f id="$id" -f sha="$HEAD_SHA" 2>&1
  echo "== exit $?"
}

cleanup() {
  call "cleanup: dequeuePullRequest" \
    'mutation($id: ID!, $sha: GitObjectID) { dequeuePullRequest(input: {id: $id}) { mergeQueueEntry { id } } }'
  call "cleanup: disablePullRequestAutoMerge" \
    'mutation($id: ID!, $sha: GitObjectID) { disablePullRequestAutoMerge(input: {pullRequestId: $id}) { pullRequest { autoMergeRequest { enabledAt } } } }'
  call "cleanup: state" \
    'query($id: ID!, $sha: GitObjectID) { node(id: $id) { ... on PullRequest { state mergeQueueEntry { state } autoMergeRequest { enabledAt } } } }'
}
trap cleanup EXIT

call "enqueuePullRequest" \
  'mutation($id: ID!, $sha: GitObjectID) { enqueuePullRequest(input: {pullRequestId: $id, expectedHeadOid: $sha}) { mergeQueueEntry { id state } } }'
call "dequeue before the auto-merge probe" \
  'mutation($id: ID!, $sha: GitObjectID) { dequeuePullRequest(input: {id: $id}) { mergeQueueEntry { id } } }'
call "enablePullRequestAutoMerge" \
  'mutation($id: ID!, $sha: GitObjectID) { enablePullRequestAutoMerge(input: {pullRequestId: $id, mergeMethod: SQUASH, expectedHeadOid: $sha}) { pullRequest { autoMergeRequest { enabledAt } mergeQueueEntry { state } } } }'
exit 0
