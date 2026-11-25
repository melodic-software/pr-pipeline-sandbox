#!/usr/bin/env bash
# resync.sh: copy every SYNCED path from claude-code-plugins into this
# sandbox's working tree and index, check the result with check-sync.sh, and
# print the evidence for condition 2 of CLAUDE.md "Merging a full resync from
# claude-code-plugins".
#
# Usage: scripts/lanes/resync.sh [<claude-code-plugins ref>] [--repo <clone>]
#
# With --repo and no ref, the clone's origin is fetched and origin/main is the
# ref. Without --repo the ref (default main) is fetched from GitHub into a
# temporary repository. Each file is the ref's blob byte for byte, with no
# attribute or line-ending conversion, and keeps its git mode. A file tracked
# here under a SYNCED path that the ref lacks is removed. LEFT_OUT, ADAPTED and
# PINNED paths (sync-lists.sh) are left alone. The changes are staged, never
# committed.
# Exit 0: in sync apart from PINNED files; the evidence is on stdout.
# Exit 1: check-sync.sh reports a difference beyond PINNED. Exit 2: bad usage.
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=sync-lists.sh
. "$here/sync-lists.sh"

usage() {
  echo "usage: $0 [<claude-code-plugins ref>] [--repo <clone>]" >&2
  exit 2
}

ref=""
repo=""
while [ $# -gt 0 ]; do
  case $1 in
    --repo)
      [ $# -ge 2 ] || usage
      repo=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$ref" ] || usage
      ref=$1
      shift
      ;;
  esac
done

root=$(git -C "$here" rev-parse --show-toplevel)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT

if [ -z "$repo" ]; then
  repo=$tmp/upstream
  git init -q "$repo"
  git -C "$repo" fetch -q --depth=1 https://github.com/melodic-software/claude-code-plugins.git "${ref:-main}"
  ref=FETCH_HEAD
elif [ -z "$ref" ]; then
  git -C "$repo" fetch -q origin
  ref=origin/main
fi
sha=$(git -C "$repo" rev-parse -q --verify "$ref^{commit}") || {
  echo "resync: $ref is not a commit in $repo" >&2
  exit 2
}

pinned_paths=("${PINNED[@]%% *}")
declare -A keep upstream
for path in "${ADAPTED[@]}" "${pinned_paths[@]}"; do keep[$path]=1; done

# 0 when the path is LEFT_OUT, ADAPTED or PINNED.
kept() {
  local prefix
  [ -z "${keep[$1]:-}" ] || return 0
  for prefix in "${LEFT_OUT[@]}"; do
    case $1 in "$prefix" | "$prefix"/*) return 0 ;; esac
  done
  return 1
}

write=() exec_files=() plain_files=()
while IFS= read -r -d '' entry; do
  meta=${entry%%$'\t'*}
  path=${entry#*$'\t'}
  kept "$path" && continue
  upstream[$path]=1
  write+=("$path")
  case $meta in
    100755*) exec_files+=("$path") ;;
    100644*) plain_files+=("$path") ;;
    *) ;;
  esac
done < <(git -C "$repo" ls-tree -r -z "$sha" -- "${SYNCED[@]}")

remove=()
while IFS= read -r -d '' path; do
  kept "$path" && continue
  [ -n "${upstream[$path]:-}" ] || remove+=("$path")
done < <(git --literal-pathspecs -C "$root" ls-files -z -- "${SYNCED[@]}")

if [ ${#remove[@]} -gt 0 ]; then
  printf '%s\0' "${remove[@]}" |
    git --literal-pathspecs -C "$root" rm -q -f --pathspec-from-file=- --pathspec-file-nul
fi

if [ ${#write[@]} -gt 0 ]; then
  # Check the blobs out through a throwaway index, reading no gitattributes, so
  # no eol or filter rule rewrites a byte.
  empty_tree=$(git -C "$repo" hash-object -t tree /dev/null)
  GIT_INDEX_FILE=$tmp/index git -C "$repo" read-tree "$sha"
  printf '%s\0' "${write[@]}" |
    GIT_INDEX_FILE=$tmp/index git -C "$repo" --attr-source="$empty_tree" \
      -c core.autocrlf=false -c core.symlinks=true \
      checkout-index -f -z --stdin --prefix="$root/"
  printf '%s\0' "${write[@]}" |
    git --literal-pathspecs -C "$root" -c core.autocrlf=false \
      add -f --pathspec-from-file=- --pathspec-file-nul
fi
# Stage each file's mode from the ref, whatever core.fileMode says.
if [ ${#exec_files[@]} -gt 0 ]; then
  printf '%s\0' "${exec_files[@]}" | git -C "$root" update-index -z --chmod=+x --stdin
fi
if [ ${#plain_files[@]} -gt 0 ]; then
  printf '%s\0' "${plain_files[@]}" | git -C "$root" update-index -z --chmod=-x --stdin
fi
echo "resync: wrote ${#write[@]} files and removed ${#remove[@]} from claude-code-plugins $sha" >&2

rc=0
out=$("$here/check-sync.sh" "$sha" --repo "$repo" 2>&1) || rc=$?
pinned_only() {
  local line path
  while IFS= read -r line; do
    for path in "${pinned_paths[@]}"; do
      case $line in "check-sync: $path "*) continue 2 ;; esac
    done
    return 1
  done <<<"$out"
}
case $rc in
  0) verdict="reports no difference" ;;
  1)
    verdict="reports only the PINNED files"
    pinned_only || {
      printf '%s\n' "$out" "resync: check-sync.sh reports a difference beyond PINNED" >&2
      exit 1
    }
    ;;
  *)
    printf '%s\n' "$out" >&2
    exit 2
    ;;
esac

printf '%s\n' \
  "Condition 2: \`scripts/lanes/check-sync.sh $sha --repo <claude-code-plugins clone>\` $verdict:" \
  "" \
  '```text' \
  "$out" \
  '```'
