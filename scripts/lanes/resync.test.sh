#!/usr/bin/env bash
# Tests for resync.sh on throwaway repositories: an upstream standing in for
# claude-code-plugins, a clone of it passed as --repo, and a sandbox holding
# resync.sh, the real check-sync.sh and a fixture sync-lists.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Keep the developer's own git configuration, and any inherited repository
# location, out of every fixture.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

g() {
  local dir=$1
  shift
  git -C "$dir" -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false "$@"
}
put() {
  mkdir -p "$(dirname "$1")"
  printf '%b' "$2" >"$1"
}
mode() { git -C "$S" ls-files -s -- "$1" | cut -d' ' -f1; }
run_resync() {
  RC=0
  OUT=$(bash "$S/scripts/lanes/resync.sh" "$@" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
}

U=$TMP/upstream C=$TMP/clone S=$TMP/sandbox

# Upstream: two commits. The second deletes sync/gone.txt and moves the
# PINNED file on. Its .gitattributes would turn x.cmd's LF into CRLF on any
# checkout that applied it.
git init -q -b main "$U"
g "$U" config core.safecrlf false
put "$U/.gitattributes" '*.cmd text eol=crlf\n'
put "$U/sync/a.txt" 'upstream a\n'
put "$U/sync/run.sh" 'echo run\n'
chmod +x "$U/sync/run.sh"
put "$U/sync/x.cmd" 'echo one\necho two\n'
put "$U/sync/gone.txt" 'removed upstream later\n'
put "$U/sync/mine.txt" 'upstream version of an adapted file\n'
put "$U/sync/pin.txt" 'pin v1\n'
put "$U/sync/out/skip.txt" 'left out\n'
put "$U/single.json" '{"upstream": true}\n'
put "$U/notsynced.txt" 'upstream only\n'
g "$U" add -A
g "$U" commit -q -m one
FIRST=$(g "$U" rev-parse HEAD)
g "$U" rm -q sync/gone.txt
put "$U/sync/pin.txt" 'pin v2\n'
put "$U/sync/a.txt" 'upstream a, second commit\n'
g "$U" add -A
g "$U" commit -q -m two
SECOND=$(g "$U" rev-parse HEAD)
git clone -q "$U" "$C"

# Sandbox: stale and extra files under the SYNCED paths, the adapted and
# pinned files as this repository keeps them, and run.sh tracked without
# its executable bit. core.fileMode false proves modes come from the ref.
git init -q -b main "$S"
g "$S" config core.fileMode false
mkdir -p "$S/scripts/lanes"
cp "$SCRIPT_DIR/check-sync.sh" "$SCRIPT_DIR/resync.sh" "$S/scripts/lanes/"
cat >"$S/scripts/lanes/sync-lists.sh" <<EOF
SYNCED=(sync single.json)
LEFT_OUT=(sync/out)
ADAPTED=(sync/mine.txt)
PINNED=("sync/pin.txt $FIRST")
EOF
put "$S/sync/a.txt" 'stale a\n'
put "$S/sync/run.sh" 'echo old run\n'
put "$S/sync/old.txt" 'only here\n'
put "$S/sync/mine.txt" 'sandbox version\n'
put "$S/sync/pin.txt" 'pin v1\n'
put "$S/unrelated.txt" 'not synced\n'
g "$S" add -A
g "$S" commit -q -m base
BASE=$(g "$S" rev-parse HEAD)

echo '# an older ref brings back what the ref holds'
run_resync "$FIRST" --repo "$C"
check 'older ref: exit 0' 0 "$RC"
check 'older ref: gone.txt is written' 'removed upstream later' "$(cat "$S/sync/gone.txt")"
check 'older ref: gone.txt is staged' 100644 "$(mode sync/gone.txt)"

echo '# origin/main by default'
run_resync --repo "$C"
check 'default ref: exit 0' 0 "$RC"
check 'default ref: the summary names origin/main' \
  "resync: wrote 4 files and removed 1 from claude-code-plugins $SECOND" "$ERR"
check 'default ref: evidence block' "$(printf '%s\n' \
  "Condition 2: \`scripts/lanes/check-sync.sh $SECOND --repo <claude-code-plugins clone>\` reports no difference:" \
  '' '```text' "check-sync: every synced file matches claude-code-plugins $SECOND" '```')" "$OUT"
RC=0
bash "$S/scripts/lanes/check-sync.sh" "$SECOND" --repo "$C" >/dev/null 2>&1 || RC=$?
check 'default ref: check-sync.sh passes on the tree on its own' 0 "$RC"
check 'synced file: content from the ref' 'upstream a, second commit' "$(cat "$S/sync/a.txt")"
check 'synced file: byte for byte, no eol conversion' \
  "$(git -C "$C" rev-parse "$SECOND:sync/x.cmd")" "$(git -C "$S" hash-object sync/x.cmd)"
check 'mode: executable bit staged from the ref' 100755 "$(mode sync/run.sh)"
check 'single synced file written' '{"upstream": true}' "$(cat "$S/single.json")"
check 'removed upstream: gone.txt leaves the index' '' "$(mode sync/gone.txt)"
check 'removed upstream: gone.txt leaves the tree' no "$([[ -e $S/sync/gone.txt ]] && echo yes || echo no)"
check 'tracked here only: old.txt removed' no "$([[ -e $S/sync/old.txt ]] && echo yes || echo no)"
check 'ADAPTED: left alone' 'sandbox version' "$(cat "$S/sync/mine.txt")"
check 'PINNED: left alone' 'pin v1' "$(cat "$S/sync/pin.txt")"
check 'LEFT_OUT: not written' no "$([[ -e $S/sync/out/skip.txt ]] && echo yes || echo no)"
check 'outside SYNCED: not written' no "$([[ -e $S/notsynced.txt ]] && echo yes || echo no)"
check 'outside SYNCED: own file kept' 'not synced' "$(cat "$S/unrelated.txt")"
check 'nothing committed' "$BASE" "$(g "$S" rev-parse HEAD)"

echo '# a PINNED difference alone passes'
put "$S/sync/pin.txt" 'pin edited here\n'
run_resync "$SECOND" --repo "$C"
check 'pinned only: exit 0' 0 "$RC"
check 'pinned only: the verdict names PINNED' \
  "Condition 2: \`scripts/lanes/check-sync.sh $SECOND --repo <claude-code-plugins clone>\` reports only the PINNED files:" \
  "$(head -1 <<<"$OUT")"
check 'pinned only: the difference is pasted' 1 "$(grep -c '^check-sync: sync/pin.txt differs from' <<<"$OUT")"

echo '# a planted difference beyond PINNED fails'
# A clean filter here rewrites a.txt as git reads it, so the copy can never
# match its blob.
put "$S/.gitattributes" 'sync/a.txt filter=planted\n'
g "$S" config filter.planted.clean 'tr a A'
run_resync "$SECOND" --repo "$C"
check 'planted: exit 1' 1 "$RC"
check 'planted: no evidence on stdout' '' "$OUT"
check 'planted: the difference is named' 1 "$(grep -c '^check-sync: sync/a.txt differs from' <<<"$ERR")"
check 'planted: the cause is named' 'resync: check-sync.sh reports a difference beyond PINNED' "$(tail -1 <<<"$ERR")"

echo '# bad usage'
run_resync no-such-ref --repo "$C"
check 'unknown ref: exit 2' 2 "$RC"
run_resync --bogus
check 'unknown flag: exit 2' 2 "$RC"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all resync.sh tests passed'
