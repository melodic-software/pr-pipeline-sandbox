#!/usr/bin/env bash
# Case 15: what select-trusted-text kept, as kinds, authors and counts only.
# No kept text is printed.
set -euo pipefail
jq -c '{pr: .pr.number, title_kept: (.pr.title != ""), items: [.items[] | {kind, author_login}], dropped}' \
  "$RUNNER_TEMP/trusted-context.json"
