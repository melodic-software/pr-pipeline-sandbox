---
name: review-gate
description: Return a gate verdict read from a fixture file. Test fixture for the pr-run-activity runner.
allowed-tools: Read
---

Read `sandbox/gate/verdict.txt` in the current working directory. Its first line is the
verdict word. Use no other tool.

If that first line, trimmed, is exactly `pass`, return verdict `pass` with summary
`review-gate: fixture says pass`. Otherwise, or if the file cannot be read, return verdict
`fail` with summary `review-gate: fixture says <the first line, or "unreadable">`.
