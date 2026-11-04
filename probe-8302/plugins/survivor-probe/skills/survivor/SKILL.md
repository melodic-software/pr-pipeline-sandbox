---
name: survivor
description: Throwaway test fixture. Start background processes and report whether they are alive. Prints process ids and counts only.
allowed-tools: Bash
---

Make exactly two Bash tool calls, one after the other, each with the command exactly as written and
with no `run_in_background` setting.

1. `${CLAUDE_SKILL_DIR}/scripts/start.sh`
2. `${CLAUDE_SKILL_DIR}/scripts/check.sh later-call 8`

Then reply with the complete output of both, verbatim, inside one fenced block, and nothing else. If
a Bash call is refused or fails, reply with the exact error text instead.
