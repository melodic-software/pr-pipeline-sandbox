---
name: fix-marker
description: Commit one base marker line to the PR branch. Test fixture for the pr-run-activity runner.
allowed-tools: Read, Edit, mcp__github_file_ops__commit_files
---

Append exactly one line, `fixed SANDBOX-BASE-MARKER-3b9e1d`, to the end of
`sandbox/refine/fix-marker.txt`. Change nothing else. Then commit that file once with the
`mcp__github_file_ops__commit_files` tool, message `test: fix-marker`. Make no other commit.
