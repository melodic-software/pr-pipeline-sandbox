# pr-pipeline-sandbox

Case 10a fixture: the base side edits this file.
Base-side line.

## Merging a full resync from claude-code-plugins

This rule is for whoever merges a full resync PR, one that copies every
`scripts/lanes/sync-lists.sh` SYNCED path from claude-code-plugins. Lanes do not apply it.
Run resyncs on demand right before a sandbox probe needs updated lane files, not proactively.
Produce the change with `scripts/lanes/resync.sh [<sha>] --repo <claude-code-plugins clone>`: it
stages the copy, runs `check-sync.sh` and prints the condition 2 evidence; commit and push as usual.

Admin-merge such a PR only when all three of these hold:

1. `ci-status` fails only because every review lane reports `failure-class=partial` or
   `failure-class=timeout`: the diff is larger than one review can read, or than one review leg
   can finish in its time limit.
2. `scripts/lanes/check-sync.sh <claude-code-plugins sha> --repo <claude-code-plugins clone>`
   reports no difference except the PINNED files.
3. No workflow run on the PR head ended in `startup_failure`. A copied file can match its source
   and still fail here, for example a copied reusable workflow that requests a permission this
   repository's callers do not grant.

Before merging, comment on the PR showing that all three hold: link the runs for conditions 1 and
3, naming each review lane's failure class, and paste the evidence `resync.sh` printed (the
`check-sync.sh` output) for condition 2, which runs only locally.
