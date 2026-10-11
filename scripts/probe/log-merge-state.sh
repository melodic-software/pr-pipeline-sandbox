#!/usr/bin/env bash
# Phase 1 probe: print the merge state of the repository in the working
# directory, every line prefixed with the label given as $1.
set -u
label=${1:?label}
say() { printf '%s %s\n' "$label" "$*"; }
if mh=$(git rev-parse -q --verify MERGE_HEAD); then say "MERGE_HEAD=$mh"; else say "MERGE_HEAD=absent"; fi
say "branch=$(git branch --show-current) head=$(git rev-parse HEAD)"
say "unmerged-names:"; git diff --name-only --diff-filter=U | sed "s/^/$label   /"
say "ls-files-u:"; git ls-files -u | sed "s/^/$label   /"
say "status-porcelain:"; git status --porcelain | sed "s/^/$label   /"
say "sha256:"; sha256sum .git/config .git/info/attributes 2>&1 | sed "s/^/$label   /"
