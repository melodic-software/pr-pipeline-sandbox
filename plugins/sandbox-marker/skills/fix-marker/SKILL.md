---
name: fix-marker
description: Append one base marker line for the runner to hand on as a patch. Test fixture for the pr-run-activity runner.
allowed-tools: Read, Edit
---

Append exactly one line, `fixed SANDBOX-BASE-MARKER-3b9e1d`, to the end of
`sandbox/refine/fix-marker.txt`. Change nothing else, and leave the change uncommitted: the
runner hands it on as a patch.
