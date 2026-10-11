#!/usr/bin/env bash
# Phase 1 probe (claude-code-plugins .work/pr-pipeline-unblock/PLAN.md step 2,
# plus the app-workflow-push open question). Runs as the pr-refine activity
# test-workflow-push, with the lanes App token the broker minted for
# mutate-branch in GH_TOKEN (contents, pull_requests and issues only, so no
# Workflows permission). Each probe merges a base into a PR branch that never
# touched .github/workflows and puts the merge on the branch three ways:
# git push, PUT update-branch, Git Data createCommit + PATCH git/refs. The ctl
# probes merge a base with no workflow change; the wfp probes merge main, whose
# side carries a .github/workflows edit. Every outcome is a log line; the
# script exits 0 unless its own setup fails.
set -uo pipefail
: "${GH_TOKEN:?}" "${PR_NUMBER:?}" "${HEAD_SHA:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"
api_url=${GITHUB_API_URL:-https://api.github.com}
repo=$GITHUB_REPOSITORY
owner=${repo%%/*}
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

echo "== committer identity with none configured"
echo "committer-ident=$(git var GIT_COMMITTER_IDENT 2>&1 | one_line)"

g fetch -q --unshallow origin '+refs/heads/main:refs/remotes/origin/main' \
  '+refs/heads/probe/*:refs/remotes/origin/probe/*' || { echo "::error::fetch failed"; exit 1; }
export GIT_AUTHOR_NAME='melodic-automation-lanes[bot]' GIT_COMMITTER_NAME='melodic-automation-lanes[bot]'
export GIT_AUTHOR_EMAIL='337595936+melodic-automation-lanes[bot]@users.noreply.github.com'
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
main=$(git rev-parse origin/main)
echo "main-tip=$main pr=$PR_NUMBER head=$HEAD_SHA"
echo "base-side-workflow-paths=$(git diff --name-only "$(git merge-base "$HEAD_SHA" "$main")" "$main" -- .github/workflows | tr '\n' ' ')"

api GET "/repos/$repo/pulls/$PR_NUMBER"
pr_ref=$(jq -r '.head.ref // empty' "$out")
echo "dispatched-pr status=$STATUS head.ref=$pr_ref mergeable=$(jq -r '.mergeable' "$out") mergeable_state=$(jq -r '.mergeable_state' "$out")"

push_probe() { # id branch base-ref
  local id=$1 branch=$2 from=$3 tip outp rc
  tip=$(git rev-parse "origin/$branch")
  git checkout -q --detach "$tip"
  if ! git merge -q --no-ff --no-edit "$from"; then
    echo "probe $id local-merge=conflict"
    git merge --abort
    return
  fi
  echo "probe $id merge-commit=$(git rev-parse HEAD) parents=$(git rev-parse HEAD^1 HEAD^2 | tr '\n' ' ')"
  echo "probe $id workflow-paths-vs-old-tip=$(git diff --name-only "$tip" HEAD -- .github/workflows | tr '\n' ' ')"
  outp=$(g push origin "HEAD:refs/heads/$branch" 2>&1)
  rc=$?
  echo "probe $id git-push-rc=$rc"
  printf '%s\n' "$outp" | sed "s/^/probe $id git-push: /"
}

update_probe() { # id branch
  local id=$1 branch=$2 number head tip i
  api GET "/repos/$repo/pulls?head=$owner:$branch&state=open"
  number=$(jq -r '.[0].number // empty' "$out")
  head=$(jq -r '.[0].head.sha // empty' "$out")
  if [ -z "$number" ]; then
    echo "probe $id no open PR for $branch"
    return
  fi
  jq -cn --arg sha "$head" '{expected_head_sha: $sha}' >"$req"
  api PUT "/repos/$repo/pulls/$number/update-branch" "$req"
  report "$id update-branch pr=$number"
  # A 202 only queues the merge, so the branch tip is re-read until it moves.
  tip=$head
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 5
    api GET "/repos/$repo/git/ref/heads/$branch"
    tip=$(jq -r '.object.sha // empty' "$out")
    [ "$tip" != "$head" ] && break
  done
  echo "probe $id tip-before=$head tip-after=$tip moved=$([ "$tip" != "$head" ] && echo yes || echo no) after-seconds=$((i * 5))"
  if [ "$tip" != "$head" ]; then
    api GET "/repos/$repo/commits/$tip"
    echo "probe $id new-tip parents=$(jq -r '[.parents[].sha] | join(",")' "$out") verified=$(jq -r '.commit.verification.verified' "$out") reason=$(jq -r '.commit.verification.reason' "$out") committer=$(jq -r '.commit.committer.name' "$out")"
  fi
}

gitdata_probe() { # id branch head base-ref
  local id=$1 branch=$2 head=$3 other f tree remote_tree commit lane omode mode sha st path
  other=$(git rev-parse "$4")
  git checkout -q --detach "$head"
  if ! git merge -q --no-commit --no-ff "$other"; then
    # The planted add/add conflict: keep both sides, branch first.
    while IFS= read -r f; do
      { git show ":2:$f"; git show ":3:$f"; } >"$f"
      git add -- "$f"
      echo "probe $id resolved-conflict=$f"
    done < <(git diff --name-only --diff-filter=U)
  fi
  tree=$(git write-tree)
  git merge --abort 2>/dev/null || git reset -q --hard "$head"
  echo "probe $id local-tree=$tree workflow-paths-vs-head=$(git diff-tree -r --name-only "$head^{tree}" "$tree" -- .github/workflows | tr '\n' ' ')"

  local entries="$RUNNER_TEMP/probe-entries.jsonl"
  : >"$entries"
  while IFS=$'\t' read -r meta path; do
    read -r omode mode _ sha st <<<"${meta#:}"
    if [ "$st" = D ]; then
      jq -cn --arg p "$path" --arg m "$omode" '{path: $p, mode: $m, type: "blob", sha: null}' >>"$entries"
      continue
    fi
    git cat-file blob "$sha" | base64 -w0 >"$RUNNER_TEMP/probe-blob.b64"
    jq -cn --rawfile c "$RUNNER_TEMP/probe-blob.b64" '{content: $c, encoding: "base64"}' >"$req"
    api POST "/repos/$repo/git/blobs" "$req"
    echo "probe $id create-blob path=$path status=$STATUS sha-match=$([ "$(jq -r '.sha // empty' "$out")" = "$sha" ] && echo yes || echo no)"
    jq -cn --arg p "$path" --arg m "$mode" --arg s "$sha" '{path: $p, mode: $m, type: "blob", sha: $s}' >>"$entries"
  done < <(git diff-tree -r --no-renames "$head^{tree}" "$tree")

  jq -cs --arg base "$(git rev-parse "$head^{tree}")" '{base_tree: $base, tree: .}' "$entries" >"$req"
  api POST "/repos/$repo/git/trees" "$req"
  remote_tree=$(jq -r '.sha // empty' "$out")
  echo "probe $id create-tree status=$STATUS tree=$remote_tree tree-match=$([ "$remote_tree" = "$tree" ] && echo yes || echo no)"
  [ -n "$remote_tree" ] || { report "$id create-tree"; return; }

  jq -cn --arg t "$remote_tree" --arg h "$head" --arg o "$other" \
    '{message: "Merge base into the PR branch (Phase 1 probe)", tree: $t, parents: [$h, $o]}' >"$req"
  api POST "/repos/$repo/git/commits" "$req"
  commit=$(jq -r '.sha // empty' "$out")
  echo "probe $id create-commit status=$STATUS commit=$commit verified=$(jq -r '.verification.verified' "$out") reason=$(jq -r '.verification.reason' "$out") parents=$(jq -r '[.parents[]?.sha] | join(",")' "$out")"
  [ -n "$commit" ] || { report "$id create-commit"; return; }

  lane="lane/probe-$id-${GITHUB_RUN_ID:-0}"
  jq -cn --arg r "refs/heads/$lane" --arg s "$commit" '{ref: $r, sha: $s}' >"$req"
  api POST "/repos/$repo/git/refs" "$req"
  report "$id create-lane-ref ref=$lane"

  api GET "/repos/$repo/git/ref/heads/$branch"
  if [ "$(jq -r '.object.sha // empty' "$out")" != "$head" ]; then
    echo "probe $id pr-branch-moved=$(jq -r '.object.sha // empty' "$out"); no fast-forward"
    return
  fi
  jq -cn --arg s "$commit" '{sha: $s, force: false}' >"$req"
  api PATCH "/repos/$repo/git/refs/heads/$branch" "$req"
  report "$id patch-pr-ref"
  if [ "$STATUS" = 200 ]; then
    echo "merge-commit=$commit"
  fi
}

echo "== control: base with no workflow change"
push_probe ctl-gitpush probe/ctl-gitpush origin/probe/ctl-base
update_probe ctl-update probe/ctl-update
gitdata_probe ctl-gitdata probe/ctl-gitdata "$(git rev-parse origin/probe/ctl-gitdata)" origin/probe/ctl-base

echo "== test: main, whose side edits .github/workflows"
push_probe wfp-gitpush probe/wfp-gitpush origin/main
update_probe wfp-update probe/wfp-update
gitdata_probe wfp-gitdata "$pr_ref" "$HEAD_SHA" origin/main

api GET "/repos/$repo/pulls/$PR_NUMBER"
echo "pulls-head=$(jq -r '.head.sha' "$out")"
git checkout -q --detach "$HEAD_SHA"
exit 0
