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
# The lists are in sync-lists.sh.
# Without --repo the ref is fetched from GitHub into a temporary repository.
# Exit 0: in sync. Exit 1: a difference, each one printed. Exit 2: bad usage.
set -euo pipefail

# shellcheck source=sync-lists.sh
. "$(dirname "$0")/sync-lists.sh"

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

left_out() {
  local prefix
  for prefix in "${LEFT_OUT[@]}"; do
    case $1 in "$prefix" | "$prefix"/*) return 0 ;; esac
  done
  return 1
}

declare -A adapted pinned
for path in "${ADAPTED[@]}"; do adapted[$path]=1; done
for entry in "${PINNED[@]}"; do pinned[${entry%% *}]=${entry#* }; done

fail=0
differ() {
  echo "check-sync: $1"
  fail=1
}

for path in "${!pinned[@]}"; do
  commit=${pinned[$path]}
  git -C "$repo" rev-parse -q --verify "$commit^{commit}" >/dev/null || commit=$(fetch "$commit")
  pinned[$path]=$commit
done

# Each lookup below is one git call over every path, not one per file.
# at["<commit> <path>"]: "<mode> <object>" of the path at that commit.
declare -A at staged hashed
load_at() {
  local commit=$1 entry meta
  shift
  while IFS= read -r -d '' entry; do
    meta=${entry%%$'\t'*}
    at["$commit ${entry#*$'\t'}"]="${meta%% *} ${meta##* }"
  done < <(git -C "$repo" ls-tree -r -z "$commit" -- "$@")
}
load_at "$ref" "${SYNCED[@]}"
for path in "${!pinned[@]}"; do load_at "${pinned[$path]}" "$path"; done

# staged[<path>]: the index mode, one line per stage.
while IFS= read -r -d '' entry; do
  path=${entry#*$'\t'}
  staged[$path]=${staged[$path]:+${staged[$path]}$'\n'}${entry%% *}
done < <(git -C "$root" ls-files -s -z -- "${SYNCED[@]}")

# Every path to compare, in SYNCED order, each group sorted.
checks=()
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
    left_out "$path" && continue
    checks+=("$path")
  done <<<"$files"
done

# hashed[<path>]: the working-tree file's blob, as hash-object computes it.
hash=()
for path in "${checks[@]}"; do
  [ ! -f "$root/$path" ] || [ -n "${hashed[$path]+set}" ] || {
    hashed[$path]=""
    hash+=("$path")
  }
done
if [ ${#hash[@]} -gt 0 ]; then
  i=0
  while IFS= read -r blob; do
    hashed[${hash[$i]}]=$blob
    i=$((i + 1))
  done < <(printf '%s\n' "${hash[@]/#/$root/}" | git -C "$root" hash-object --stdin-paths)
fi

for path in "${checks[@]}"; do
  commit=${pinned[$path]:-$ref}
  if [ -n "${at["$commit $path"]+set}" ]; then
    want=${at["$commit $path"]}
  else
    # Not a file at the commit: ask for the path itself, which may be a tree.
    want=$(git -C "$repo" ls-tree "$commit" -- "$path" | awk '{print $1, $3}')
  fi
  if [ ! -f "$root/$path" ]; then
    [ -z "$want" ] || differ "$path is missing here"
    continue
  fi
  if [ -z "$want" ]; then
    differ "$path is not at $commit"
    continue
  fi
  have="${staged[$path]:-untracked} ${hashed[$path]}"
  [ "$have" = "$want" ] || differ "$path differs from $commit ($have, want $want)"
done

if [ "$fail" = 0 ]; then
  echo "check-sync: every synced file matches claude-code-plugins $ref"
fi
exit "$fail"
