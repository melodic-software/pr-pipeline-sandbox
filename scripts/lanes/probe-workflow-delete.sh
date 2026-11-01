#!/usr/bin/env bash
# Probe for claude-code-plugins resolve-conflicts workflow-staged: runs as the
# pr-refine activity test-workflow-delete with the lanes App token the broker
# minted for mutate-branch in GH_TOKEN (no Workflows permission). It merges
# main into the fixture PR head, whose tree keeps a workflow main deleted, and
# puts the merge on the PR branch the way apply-patch.mjs does: POST git/trees
# with base_tree = the head's tree and the deleted path as sha null, POST
# git/commits with parents [head, main], PATCH git/refs force false. If that
# is refused, a second probe drops only the workflow, to tell the deletion from
# the rest of the merge. Every outcome is a log line; the script exits 0 unless
# its own setup fails.
set -uo pipefail
: "${GH_TOKEN:?}" "${PR_NUMBER:?}" "${HEAD_SHA:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"
api_url=${GITHUB_API_URL:-https://api.github.com}
repo=$GITHUB_REPOSITORY
out=$RUNNER_TEMP/probe-response.json
req=$RUNNER_TEMP/probe-request.json

one_line() { tr -cd '[:print:]' | cut -c1-700; }

# api METHOD PATH [REQUEST-FILE]: sets STATUS and BODY; the full body stays in $out.
api() {
  local args=(-sS -o "$out" -w '%{http_code}' -X "$1" -H @-
    -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
  if [ -n "${3:-}" ]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$3")
  fi
  STATUS=$(printf 'Authorization: Bearer %s\n' "$GH_TOKEN" | curl "${args[@]}" "$api_url$2") || STATUS=000
  BODY=$(one_line <"$out" 2>/dev/null || true)
}
report() { echo "probe $1 status=$STATUS body=$BODY"; }

basic=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)
echo "::add-mask::$basic"
g() { GIT_TERMINAL_PROMPT=0 git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $basic" "$@"; }

g fetch -q --unshallow origin '+refs/heads/main:refs/remotes/origin/main' 2>/dev/null ||
  g fetch -q origin '+refs/heads/main:refs/remotes/origin/main' || { echo "::error::fetch failed"; exit 1; }
export GIT_AUTHOR_NAME='melodic-automation-lanes[bot]' GIT_COMMITTER_NAME='melodic-automation-lanes[bot]'
export GIT_AUTHOR_EMAIL='337595936+melodic-automation-lanes[bot]@users.noreply.github.com'
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
main=$(git rev-parse origin/main)
api GET "/repos/$repo/pulls/$PR_NUMBER"
branch=$(jq -r '.head.ref // empty' "$out")
echo "main-tip=$main pr=$PR_NUMBER head=$HEAD_SHA branch=$branch"
echo "head-workflows-missing-on-main=$(comm -23 <(git ls-tree -r --name-only "$HEAD_SHA" -- .github/workflows | sort) <(git ls-tree -r --name-only "$main" -- .github/workflows | sort) | tr '\n' ' ')"

# put ID TREE PARENTS-JSON: create-tree from the head's tree, create-commit,
# PATCH the PR branch. Sets PUT_OK=yes on a 200 ref update.
put() {
  local id=$1 tree=$2 parents=$3 entries="$RUNNER_TEMP/probe-entries.jsonl" omode mode sha st meta path remote_tree commit
  PUT_OK=no
  : >"$entries"
  while IFS=$'\t' read -r meta path; do
    read -r omode mode _ sha st <<<"${meta#:}"
    if [ "$st" = D ]; then
      jq -cn --arg p "$path" --arg m "$omode" '{path: $p, mode: $m, type: "blob", sha: null}' >>"$entries"
    else
      jq -cn --arg p "$path" --arg m "$mode" --arg s "$sha" '{path: $p, mode: $m, type: "blob", sha: $s}' >>"$entries"
    fi
  done < <(git diff-tree -r --no-renames "$HEAD_SHA^{tree}" "$tree")
  echo "probe $id entries=$(jq -cs '[.[] | {path, sha}]' "$entries")"
  jq -cs --arg base "$(git rev-parse "$HEAD_SHA^{tree}")" '{base_tree: $base, tree: .}' "$entries" >"$req"
  api POST "/repos/$repo/git/trees" "$req"
  remote_tree=$(jq -r '.sha // empty' "$out")
  echo "probe $id create-tree status=$STATUS tree=$remote_tree tree-match=$([ "$remote_tree" = "$tree" ] && echo yes || echo no)"
  [ -n "$remote_tree" ] || { report "$id create-tree"; return; }
  jq -cn --arg t "$remote_tree" --argjson p "$parents" \
    '{message: "Merge main into the PR branch (workflow-deletion probe)", tree: $t, parents: $p}' >"$req"
  api POST "/repos/$repo/git/commits" "$req"
  commit=$(jq -r '.sha // empty' "$out")
  echo "probe $id create-commit status=$STATUS commit=$commit verified=$(jq -r '.verification.verified' "$out") reason=$(jq -r '.verification.reason' "$out") parents=$(jq -r '[.parents[]?.sha] | join(",")' "$out")"
  [ -n "$commit" ] || { report "$id create-commit"; return; }
  jq -cn --arg s "$commit" '{sha: $s, force: false}' >"$req"
  api PATCH "/repos/$repo/git/refs/heads/$branch" "$req"
  report "$id patch-pr-ref"
  if [ "$STATUS" = 200 ]; then
    PUT_OK=yes
    api GET "/repos/$repo/git/trees/$commit?recursive=1"
    echo "probe $id new-tip=$commit tip-has-deleted-workflow=$(jq -r '[.tree[].path] | any(. == ".github/workflows/rate-probe.yml")' "$out")"
  fi
}

echo "== lane shape: merge main into the head"
git checkout -q --detach "$HEAD_SHA"
if ! git merge -q --no-commit --no-ff "$main"; then
  echo "::error::the fixture merge conflicts"
  git merge --abort
  exit 1
fi
tree=$(git write-tree)
git merge --abort 2>/dev/null || git reset -q --hard "$HEAD_SHA"
echo "merge-tree=$tree workflow-paths-vs-head=$(git diff-tree -r --name-status "$HEAD_SHA^{tree}" "$tree" -- .github/workflows | tr '\t\n' ': ')"
put merge "$tree" "$(jq -cn --arg h "$HEAD_SHA" --arg m "$main" '[$h, $m]')"

if [ "$PUT_OK" != yes ]; then
  echo "== isolate: drop only the workflow main deleted"
  GIT_INDEX_FILE=$RUNNER_TEMP/probe-index git read-tree "$HEAD_SHA^{tree}"
  GIT_INDEX_FILE=$RUNNER_TEMP/probe-index git rm -q --cached -- .github/workflows/rate-probe.yml
  only=$(GIT_INDEX_FILE=$RUNNER_TEMP/probe-index git write-tree)
  put delete-only "$only" "$(jq -cn --arg h "$HEAD_SHA" '[$h]')"
fi

api GET "/repos/$repo/pulls/$PR_NUMBER"
echo "pulls-head=$(jq -r '.head.sha' "$out")"
git checkout -q --detach "$HEAD_SHA"
exit 0
