# Workflow jobs

One section per workflow file under `.github/workflows/`, in file-name order, with one entry per
job in the order the file lists them. A job that sets no `needs:`, `if:` or `permissions:` key of
its own says so; where it has no `permissions:` map, the workflow-level map it inherits is quoted
instead. A step with no `name:` is listed by its `uses:` or `run:` and marked unnamed. A job that
calls a reusable workflow (`uses:` at job level) has no steps of its own; its entry names the
workflow it calls.

## pr-check-managed-files.yml

### check-managed-files

Checks out the full history and runs the `check-managed-files` action from `ci-workflows`, pointed
at `melodic-software/claude-code-plugins` so the check has a real managed-path set. On a
`merge_group` run the action maps the group to its pull requests and checks each one's own diff.
It is advisory: it is not part of `ci-status`.

- `needs:` none
- `if:` none
- `permissions:` none at job level; inherits the workflow map:

  ```yaml
  permissions:
    contents: read
    pull-requests: read
  ```

- Steps:
  1. (unnamed) `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`
  2. (unnamed) `uses: melodic-software/ci-workflows/.github/actions/check-managed-files@3a2c748fdef9cfb9ceec5a66289e21842189689f`

## pr-feedback-dispatch.yml

### dispatch

Runs when a `pr-review-hosted` or `pr-review-security-hosted` run completes on a same-repository
pull request, and runs `feedback-dispatch.mjs` to dispatch `pr-unblock.yml`'s address-feedback
activity once both review lanes have reviewed the PR's current head and an unresolved thread needs
it. It honors the lanes kill switch, restores and saves a per-head dispatch record in the Actions
cache, and uploads an artifact naming the run it dispatched and the review run that started it.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    github.ref == 'refs/heads/main'
    && github.event.workflow_run.event == 'pull_request'
    && github.event.workflow_run.head_repository.full_name == github.repository
    && github.event.workflow_run.conclusion != 'skipped'
    && github.event.workflow_run.conclusion != 'cancelled'
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out main
    pull-requests: read # the PR, its comments and review threads
    checks: read # skip a head that already has an address-feedback check run
    actions: write # list pr-unblock runs; dispatch pr-unblock.yml
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Log the API budget at the start
  4. Check the kill switch
  5. Report the kill switch
  6. Install resolve-config's dependencies
  7. Restore the dispatch record for this head
  8. Dispatch address-feedback
  9. Save the dispatch record for this head
  10. Name the dispatched-run record
  11. Record the dispatched run
  12. Log the API budget at the end

### rerun-ci-status

When either review workflow completes on a same-repository pull request, re-runs the `ci-status`
job of the newest `pr-require-checks` run on that head so it reads the finished review. It skips a
closed PR, a head the PR has moved past, and a `ci-status` job that has not started; one in progress
is polled every 60 seconds for at most 10 minutes before the re-run.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    github.ref == 'refs/heads/main'
    && (github.event.workflow_run.path == '.github/workflows/pr-review-hosted.yml'
    || github.event.workflow_run.path == '.github/workflows/pr-review-security-hosted.yml')
    && github.event.workflow_run.event == 'pull_request'
    && github.event.workflow_run.conclusion != 'skipped'
    && github.event.workflow_run.repository.full_name == github.repository
    && github.event.workflow_run.head_repository.full_name == github.repository
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: write # list pr-require-checks runs and jobs; re-run the ci-status job
    pull-requests: read # the PR's state and live head
  ```

- Steps:
  1. Re-run ci-status on the reviewed head

## pr-merge.yml

### merge

Lists the open, non-draft PRs into `main` that the lanes App opened and runs the babysit merge gate
on each with a lanes App token from the broker. When the gate passes and `merge.report-only` is off,
the gate adds the PR to the merge queue at the commit it checked. The job also runs the read-only
post-merge check on earlier lane merges, writes a summary of every verdict, and revokes the lane
token at the end.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    github.ref == 'refs/heads/main'
    && (github.event_name != 'pull_request_target'
    || github.event.pull_request.head.repo.full_name == github.repository)
    && (github.event_name != 'workflow_run'
    || github.event.workflow_run.head_repository.full_name == github.repository)
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out main
    pull-requests: read # list the open PRs
    id-token: write # prove to the token broker which workflow this is
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Check the kill switch
  4. Report the kill switch
  5. Check who started the run
  6. Resolve the config
  7. Read report-only
  8. Request the lane token
  9. List the candidate PRs
  10. Run the merge gate on each candidate
  11. Check earlier lane merges
  12. Write the summary
  13. Revoke the lane token

### dispatch-full-run

Starts a full `pr-require-checks.yml` run on `main` with the job's own token when the `merge` job
reports that a lane merge needs one, since the lanes App token cannot start workflows. It then
uploads an artifact naming the run it started, which the post-merge check needs before it counts a
run started by `github-actions[bot]`.

- `needs:` `needs: merge`
- `if:`

  ```yaml
  if: needs.merge.outputs.dispatch == 'true' && github.event_name != 'pull_request_target'
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: write # start pr-require-checks.yml on main
  ```

- Steps:
  1. Start the full CI run on main
  2. Record the dispatched run

## pr-refine.yml

### fix-marker

Runs the `pr-refine` lane's `fix-marker` write activity through `pr-run-activity-write.yml` in the
`automations` role, on a pull request event or a `refine` dispatch. A pull request event the lanes
App sent does not start it. It joins the per-PR write queue, which queues runs and never cancels
them.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    !(github.event_name == 'pull_request'
    && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID)
    && (inputs.activity == '' || inputs.activity == 'refine')
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-write.yml`.

### audit-env-write

Runs the `pr-refine` lane's `audit-env-write` activity through `pr-run-activity-write.yml` in the
`automations` role, under the same trigger condition as `fix-marker`. It shares the same per-PR
write queue.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    !(github.event_name == 'pull_request'
    && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID)
    && (inputs.activity == '' || inputs.activity == 'refine')
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-write.yml`.

### fix-ci-context

A sandbox-only probe of `fix-ci`'s subscription fallback, run on a `fix-ci-fallback` dispatch. It
checks out the default branch, checks the kill switch, writes the failing checks' context for the
dispatched PR with `fix-ci-context.mjs`, and uploads it as an artifact. Its outputs carry the
gated head SHA and the context's hash and attempt to the later jobs.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    github.event_name == 'workflow_dispatch' && inputs.activity == 'fix-ci-fallback'
    && format('{0}', github.event.sender.id) != vars.AUTOMATION_LANES_APP_SENDER_ID
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out main
    pull-requests: read # the PR's head and commits
    checks: read # the head's check runs and their annotations
    actions: read # each failing job's workflow file and log
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Check the kill switch
  4. Install resolve-config's dependencies
  5. Write the failing checks' context
  6. Upload the context

### fix-ci

Runs the `fix-ci` activity through `pr-run-activity-read.yml` on the context `fix-ci-context`
gated. It passes an API-key secret that is never set, so the call reports no credential and hands
off to `fix-ci-subscription`.

- `needs:` `needs: fix-ci-context`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-read.yml`.

### fix-ci-subscription

Re-runs the `fix-ci` activity through `pr-run-activity-read.yml` on
`AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` when the first call hit a credit stop or had no credential.
It passes the matching `fallback` value (`credit-stop` or `no-key`).

- `needs:` `needs: [fix-ci-context, fix-ci]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true'
    && (needs.fix-ci.outputs.lane-class == 'credit-stop'
    || needs.fix-ci.outputs.credential-present == 'false') }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-read.yml`.

### apply-patch

Applies the patch the `fix-ci` or `fix-ci-subscription` call wrote, through
`pr-run-activity-write.yml`'s `apply-patch` activity. It pins the patch to the head
`fix-ci-context` gated.

- `needs:` `needs: [fix-ci-context, fix-ci, fix-ci-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && ((needs.fix-ci-subscription.outputs.patch-state || needs.fix-ci.outputs.patch-state) == 'written'
    || (needs.fix-ci-subscription.outputs.patch-state || needs.fix-ci.outputs.patch-state) == 'empty') }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-write.yml`.

### fix-docs

Runs main's `fix-docs` activity through `pr-run-activity-read.yml`, on a `fix-docs` or
`fix-docs-no-key` dispatch, or on a non-draft pull request from the `test/probe-7-1-fix-docs`
branch that neither the lanes App nor a bot sent. For `fix-docs-no-key` it passes an empty API
key, so the call hands off to `fix-docs-subscription`.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    (github.event_name == 'workflow_dispatch'
    && (inputs.activity == 'fix-docs' || inputs.activity == 'fix-docs-no-key'))
    || (github.event_name == 'pull_request'
    && github.head_ref == 'test/probe-7-1-fix-docs'
    && !github.event.pull_request.draft
    && format('{0}', github.event.sender.id) != vars.AUTOMATION_LANES_APP_SENDER_ID
    && github.event.sender.type != 'Bot')
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-read.yml`.

### fix-docs-subscription

Re-runs `fix-docs` through `pr-run-activity-read.yml` on `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` when
the first call hit a credit stop or had no credential, passing the matching `fallback` value.

- `needs:` `needs: fix-docs`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && (needs.fix-docs.outputs.lane-class == 'credit-stop'
    || needs.fix-docs.outputs.credential-present == 'false') }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-read.yml`.

### apply-docs-patch

Applies the patch `fix-docs` or `fix-docs-subscription` wrote, through
`pr-run-activity-write.yml`'s `apply-patch` activity, pinned to the head that call reported.

- `needs:` `needs: [fix-docs, fix-docs-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && (needs.fix-docs-subscription.outputs.patch-state || needs.fix-docs.outputs.patch-state) == 'written' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-write.yml`.

## pr-require-checks.yml

### check-force-red

Checks out the tested commit (the PR's merge commit, or the queued merge commit on `merge_group`)
and fails when a `.ci-force-red` file exists at the repository root. It is the gate that lets a
sandbox PR force `ci-status` red on purpose.

- `needs:` none
- `if:` none
- `permissions:` none at job level; inherits the workflow map:

  ```yaml
  permissions:
    contents: read
  ```

- Steps:
  1. (unnamed) `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`
  2. Fail when .ci-force-red exists

### ci-status

The aggregate `ci-status` check the merge-queue and ci-gate rulesets require. It fails unless
`check-force-red` succeeded. On a `pull_request` event it also fails while the PR carries the
human-gated label, when a review-lane hold was lifted by an account not on the trusted-actor list,
and until both review lanes have reviewed the head; a draft skips the review-lane requirement.

- `needs:` `needs: [check-force-red]`
- `if:`

  ```yaml
  if: ${{ !cancelled() }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # the review lanes' runs and jobs
    contents: read # .work-item-tracker.json and trusted-actors.json at the base
    issues: read # the PR's labels, comments and label events
    pull-requests: read # the PR and its files
  ```

- Steps:
  1. Aggregate gate results
  2. Note a draft
  3. Fail a pull request carrying the human-gated label
  4. Fail a review-lane hold an untrusted account lifted
  5. Require both review lanes on this head

## pr-review-hosted.yml

### kill-switch

Checks out the kill-switch action from `main` and reads the lanes kill switch, since the reusable
review workflow reads none. Its `proceed` output is `true` only when the lanes switch lets the run
proceed and `CLAUDE_REVIEW_DISABLED` is not `true`; otherwise its `Report the kill switch` step
records the stop, which `ci-status` counts as a stopped lane.

- `needs:` none
- `if:`

  ```yaml
  if: github.event.pull_request.draft == false
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out the default branch for the kill-switch action
  ```

- Steps:
  1. Check out the default branch
  2. Set up Node
  3. Check the kill switch
  4. Report the kill switch

### pr-review

Calls the org `pr-review-cli.yml` reusable workflow for the `code` review lane, publishing comments,
when the kill switch lets it proceed. The job id keeps the check name
`pr-review / claude-review-status` that `ci-status` reads. A hold adds the `needs-human` label and
a `claude-lane-hold` marker comment.

- `needs:` `needs: [kill-switch]`
- `if:`

  ```yaml
  if: ${{ !cancelled() && github.event.pull_request.draft == false && needs.kill-switch.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # the reusable's check-key-credit job reads this workflow's
                  # runs for the key's recent credit stop
    contents: read
    pull-requests: write # the review, its comments, the marker and the hold label
  ```

- Steps: none; calls
  `melodic-software/ci-workflows/.github/workflows/pr-review-cli.yml@4fbceb4b75ffd568dfa5db31de0d0e753c0c64e6`.

## pr-review-no-bots.yml

### pr-review-no-bots

A sandbox control that calls the org `pr-review.yml` reusable workflow with an empty
`allowed-bot-sender-ids`, so a lanes App push is skipped. Its `docs-only-paths` of `"**"` matches
every file, so a human event runs no model either.

- `needs:` none
- `if:`

  ```yaml
  if: github.event.pull_request.draft == false
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: write
    id-token: write
  ```

- Steps: none; calls
  `melodic-software/ci-workflows/.github/workflows/pr-review.yml@a92020292976c2e9b50f7adc922693a45a6c1226`.

## pr-review-security-hosted.yml

### kill-switch

Checks out the kill-switch action from `main` and reads the lanes kill switch for the security
review. Its `proceed` output is `true` only when the lanes switch lets the run proceed and
`CLAUDE_SECURITY_REVIEW_DISABLED` is not `true`; otherwise its `Report the kill switch` step
records the stop.

- `needs:` none
- `if:`

  ```yaml
  if: github.event.pull_request.draft == false
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out the default branch for the kill-switch action
  ```

- Steps:
  1. Check out the default branch
  2. Set up Node
  3. Check the kill switch
  4. Report the kill switch

### pr-review-security

Calls the org `pr-review-cli.yml` reusable workflow for the `security` review lane, publishing
comments, when the kill switch lets it proceed. The job id keeps the check name
`pr-review-security / security-review` that `ci-status` reads. Docs-only Markdown changes skip the
model, and a hold adds the `needs-human` label and a `claude-lane-hold` marker comment.

- `needs:` `needs: [kill-switch]`
- `if:`

  ```yaml
  if: ${{ !cancelled() && github.event.pull_request.draft == false && needs.kill-switch.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # the reusable's check-key-credit job reads this workflow's
                  # runs for the key's recent credit stop
    contents: read
    pull-requests: write # the review, its comments, the marker and the hold label
  ```

- Steps: none; calls
  `melodic-software/ci-workflows/.github/workflows/pr-review-cli.yml@4fbceb4b75ffd568dfa5db31de0d0e753c0c64e6`.

## pr-run-activity-read-probe.yml

### read-token

A test call of `pr-run-activity-read.yml` for case 6: the `pr-run-checks` lane's
`check-read-token` read script activity, expected to succeed. It passes only the scan-carrier key,
so no App key or OAuth token reaches the run.

- `needs:` none
- `if:` none
- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-read.yml`.

### write-via-read

A test call of `pr-run-activity-read.yml` for case 7a: the `pr-refine` lane's
`check-write-effect` activity, a mutate-branch activity sent to the read workflow. It is expected
to fail with `effect-not-read` before the head checkout.

- `needs:` none
- `if:` none
- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    checks: write
    issues: write
    id-token: write
  ```

- Steps: none; calls `./.github/workflows/pr-run-activity-read.yml`.
