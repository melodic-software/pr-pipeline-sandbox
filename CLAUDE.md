# pr-pipeline-sandbox

Case 10a fixture: the base side edits this file.
Base-side line.

## Merging a full resync from claude-code-plugins

This rule is for whoever merges a full resync PR, one that copies every
`scripts/lanes/check-sync.sh` SYNCED path from claude-code-plugins. Lanes do not apply it.

Admin-merge such a PR only when all three of these hold:

1. `ci-status` fails only because both review lanes report `failure-class=partial`: the diff is
   larger than one review can read.
2. `scripts/lanes/check-sync.sh <claude-code-plugins sha> --repo <claude-code-plugins clone>`
   reports no difference except the PINNED files.
3. No workflow run on the PR head ended in `startup_failure`. A copied file can match its source
   and still fail here, for example a copied reusable workflow that requests a permission this
   repository's callers do not grant.

Before merging, comment on the PR stating which of the three conditions hold, with a link to the
run behind each one.
