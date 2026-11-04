---
name: scan-environ
description: Run the scan-environ verify-script wrapper and report its output. Test fixture for the pr-run-activity runner.
allowed-tools: Bash
---

Run the `scan-environ` verification wrapper your instructions name, by exactly that path, with no
arguments, as one Bash call. It prints process names and key names, never a value. Then reply with
its complete output, including its exit status line, verbatim, inside one fenced block, and nothing
else. If the Bash call is refused or fails, reply with the exact error text instead.
