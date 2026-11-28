#!/usr/bin/env bash
set -euo pipefail
jq -c '{pr: .pr.number, title_kept: (.pr.title != ""), items: [.items[] | {kind, author_login}], dropped}' \
  "$RUNNER_TEMP/trusted-context.json"
