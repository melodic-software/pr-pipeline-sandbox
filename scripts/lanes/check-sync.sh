#!/usr/bin/env bash
# check-sync.sh: assert the lane runtime synced from claude-code-plugins is
# byte-identical to it.
#
# Usage: scripts/lanes/check-sync.sh <claude-code-plugins ref> [--repo <clone>]
#
# Every file under a SYNCED path must exist at the ref with the same content
# and git mode, and every file the ref holds there must exist here. ADAPTED
# files are this sandbox's own versions and are not compared. A PINNED file
# is compared against its own claude-code-plugins commit instead of the ref.
# Without --repo the ref is fetched from GitHub into a temporary repository.
# Exit 0: in sync. Exit 1: a difference, each one printed. Exit 2: bad usage.
set -euo pipefail

SYNCED=(
  .github/actions/check-kill-switch
  .github/actions/check-signed-commits
  .github/actions/check-trusted-base
  .github/actions/check-trusted-trigger
  .github/actions/check-wip-cap
  .github/actions/collect-base-activity
  .github/actions/log-api-budget
  .github/actions/open-lane-output
  .github/actions/report-check-run
  .github/actions/request-lane-token
  .github/actions/resolve-config
  .github/actions/seal-lane-output
  .github/actions/select-trusted-text
  .github/actions/setup-runner-isolation
  .github/lane-keys
  .github/scripts/apply-patch
  .github/scripts/merge-base
  .github/scripts/pr-unblock
  .github/scripts/read-patch
  .github/scripts/work-resolve-issue
  # Modules the synced scripts and tests import from outside those folders.
  .github/scripts/intake-triage/admit.mjs
  .github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs
  .github/scripts/pr-merge/merge-holds.mjs
  .github/scripts/pr-verify/write-verdict.mjs
  .github/standards/dependabot-policy
  .github/standards/github-actions-conventions
  .github/standards/runner-policy
  .github/standards/trusted-actors
  .github/workflows/pr-feedback-dispatch.yml
  .github/workflows/pr-run-activity-read.yml
  .github/workflows/pr-run-activity-write.yml
  .github/workflows/pr-unblock-dispatch.yml
  .github/workflows/pr-unblock.yml
  .github/workflows/work-resolve-issue.yml
  docs/conventions/pr-pipeline/examples
  docs/conventions/pr-pipeline/pr-pipeline.schema.json
  # What the read runner's skill setup, leak scan and role routes read from
  # the base.
  .github/requirements-ci.txt
  .python-version
  lib/publish-gate.mjs
  package-lock.json
  package.json
  plugins/multi-agent/reference/defaults.yaml
  scripts/setup-env.sh
  # The read runner's caller-secret gate, and the shadow check the owner runs
  # after the scan-carrier keygen.
  scripts/check-read-caller-keys.mjs
  scripts/check-read-caller-keys.sh
  scripts/check-scan-carrier-secret-shadow.sh
)

# The sandbox's own versions of files claude-code-plugins also has.
ADAPTED=(
  # Sandbox activities and lanes, migrated to schema version 2.
  # review-dependency, apply-dependency-verdict, fix-ci and apply-ci-fix are
  # main's, unchanged; resolve-issue takes main's labels and holds but keeps
  # no checks.
  docs/conventions/pr-pipeline.yaml
  # Sandbox activities fix-marker and audit-env-write, with the role input,
  # and the fix-ci fallback probe (pr-unblock.yml's fix-ci jobs on this lane).
  .github/workflows/pr-refine.yml
  # The synced dispatch job plus claude-code-plugins#9361's rerun-ci-status
  # job, ahead of the next full resync.
  .github/workflows/pr-feedback-dispatch.yml
  # The sandbox's own scan-carrier key pair: one per repository, never shared.
  # Until the owner runs keygen here it is the placeholder line, so seal fails
  # closed.
  .github/lane-keys/scan-carrier.pub
)

# "<path> <commit>": compared against that commit instead of the ref.
PINNED=(
  # A sync-manifest-managed file: check-managed-files refuses a hand edit, and
  # nothing in the lane runtime reads it.
  ".github/standards/runner-policy/policy.json 9329c4cd64765267e43aef0ceef58c40961cd676"
)

usage() {
  echo "usage: $0 <claude-code-plugins ref> [--repo <clone>]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
ref=$1
shift
repo=""
while [ $# -gt 0 ]; do
  case $1 in
    --repo)
      [ $# -ge 2 ] || usage
      repo=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
tmp=""
trap '[ -z "$tmp" ] || rm -rf "${tmp:?}"' EXIT

fetch() {
  local want=$1
  git -C "$repo" fetch -q --depth=1 https://github.com/melodic-software/claude-code-plugins.git "$want"
  git -C "$repo" rev-parse FETCH_HEAD
}

if [ -z "$repo" ]; then
  tmp=$(mktemp -d)
  repo=$tmp
  git -C "$repo" init -q --bare
  ref=$(fetch "$ref")
fi
git -C "$repo" rev-parse -q --verify "$ref^{commit}" >/dev/null || {
  echo "check-sync: $ref is not a commit in $repo" >&2
  exit 2
}

declare -A adapted pinned
for path in "${ADAPTED[@]}"; do adapted[$path]=1; done
for entry in "${PINNED[@]}"; do pinned[${entry%% *}]=${entry#* }; done

fail=0
differ() {
  echo "check-sync: $1"
  fail=1
}

# "<mode> <blob>" of a path at a commit, or nothing.
at_ref() {
  git -C "$repo" ls-tree "$1" -- "$2" | awk '{print $1, $3}'
}

compare() {
  local path=$1 commit=$2 want have mode
  want=$(at_ref "$commit" "$path")
  if [ ! -f "$root/$path" ]; then
    [ -z "$want" ] || differ "$path is missing here"
    return
  fi
  if [ -z "$want" ]; then
    differ "$path is not at $commit"
    return
  fi
  mode=$(git -C "$root" ls-files -s -- "$path" | awk '{print $1}')
  [ -n "$mode" ] || mode=untracked
  have="$mode $(git -C "$root" hash-object -- "$root/$path")"
  [ "$have" = "$want" ] || differ "$path differs from $commit ($have, want $want)"
}

for path in "${!pinned[@]}"; do
  commit=${pinned[$path]}
  git -C "$repo" rev-parse -q --verify "$commit^{commit}" >/dev/null || commit=$(fetch "$commit")
  pinned[$path]=$commit
done

for synced in "${SYNCED[@]}"; do
  files=$({
    git -C "$repo" ls-tree -r --name-only "$ref" -- "$synced"
    git -C "$root" ls-files -- "$synced"
    for path in "${!pinned[@]}"; do
      case $path in "$synced" | "$synced"/*) echo "$path" ;; esac
    done
  } | sort -u)
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -z "${adapted[$path]:-}" ] || continue
    compare "$path" "${pinned[$path]:-$ref}"
  done <<<"$files"
done

if [ "$fail" = 0 ]; then
  echo "check-sync: every synced file matches claude-code-plugins $ref"
fi
exit "$fail"
