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
closed PR, a head the PR has moved past, and a `ci-status` job that has not started; a run in
progress is polled every 60 seconds and its `ci-status` re-run once it completes, but a run still
going after 600 seconds fails the job with no re-run.

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
`pr-review-security / security-review` that `ci-status` reads. A change only to its docs-only paths
(`docs/**/*.md`, `**/README.md` and `**/CHANGELOG.md`) skips the model, and a hold adds the
`needs-human` label and a `claude-lane-hold` marker comment.

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

## pr-run-activity-read.yml

### broker-check

Checks out the default branch tip, reads the lanes kill switch, and, when it lets the run proceed,
asks the lanes token broker's check endpoint whether the lane and activity may run. It is the only
job in the file that holds `id-token: write`, and it never checks out the PR head. Its `allowed`
output is the broker step's success and its `attempt` output the run attempt, so the `run` job can
refuse an allow reused from an earlier attempt.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    !(github.event_name == 'pull_request'
    && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID)
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    id-token: write
  ```

- Steps:
  1. Assert the default branch is set
  2. Check out the default branch tip
  3. Set up Node
  4. Check the kill switch
  5. Ask the broker whether the lane may run

### broker-allowed

Job-level evidence of the broker's allow for a caller's handoff read: it runs, and succeeds, only
when `broker-check` reports `allowed`, and is skipped otherwise. It needs `broker-check` alone, so
no `run` job output reaches it.

- `needs:` `needs: broker-check`
- `if:`

  ```yaml
  if: needs.broker-check.outputs.allowed == 'true'
  ```

- `permissions:` `permissions: {}`
- Steps:
  1. Record the broker's allow

### run

Runs one read activity of one lane. From the default branch tip it checks the kill switch, the
broker's allow for this attempt, the trigger, the trusted base and the resolved config, and fails
before the head checkout on any effect but `read` or a mismatched prepare mode, merge input or
launcher input. It then checks out the PR head (in issue mode the trusted base or a resumed lane
branch's tip), runs the skill on `run-claude-cli` with the API key or the OAuth token, or runs the
script, and collects the patch or checks the tree is clean; every payload leaves only as sealed
outputs for the `scan` job.

- `needs:` `needs: broker-check`
- `if:`

  ```yaml
  if: >-
    !(github.event_name == 'pull_request'
    && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID)
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
  ```

- Steps:
  1. Assert the lanes App sender id and default branch are set
  2. Check out the default branch tip
  3. Set up Node
  4. Check the kill switch
  5. Assert the broker allowed this attempt
  6. Check the trigger
  7. Assert the gated head is the caller's
  8. Assert the base is on the default branch
  9. Resolve the config
  10. Assert the effect is read
  11. Assert an issue activity is in patch mode
  12. Assert a gate activity is not in patch mode
  13. Assert the prepare mode is ci-context, review-threads, dependency-review or merge-base in patch mode
  14. Assert a feedback context goes with review-threads
  15. Check the merge inputs
  16. Check the launcher's inputs
  17. Check the run's workflow files against main
  18. Stop on stale workflow files
  19. Check for an earlier run's work on the issue
  20. Decide whether the activity runs
  21. Download the CI context
  22. Check the CI context
  23. Download the feedback context
  24. Check the feedback context
  25. Download the dependency context
  26. Check the dependency context
  27. Select the trusted PR text
  28. Stage the activity from the base
  29. Write the issue for the skill
  30. Apply the Claude managed settings
  31. Isolate the runner
  32. Copy the dependency setup from the base
  33. Copy the patch collector and the output sealer from the base
  34. Copy the merge scripts from the base
  35. Check out the PR head
  36. Assert the head is the gated SHA
  37. Merge the base into the head
  38. Stage the skill's files in the checkout
  39. Set up Python for the skill
  40. Install the skill's dependencies
  41. Check the API key
  42. Check the OAuth token
  43. Run the skill on the API key
  44. Check the API key leg's permission mode
  45. Run the skill on the OAuth token
  46. Check the OAuth token leg's permission mode
  47. Write the skill's final reply
  48. Write the skill's structured output
  49. Check the skill took a model turn
  50. Read the run's API error
  51. Record the launcher's lane outcome
  52. Run the script activity
  53. Check the working tree is clean
  54. Collect the patch
  55. Remove the checkouts' .git directories
  56. Collect the issue outcome
  57. Stage the reply, run fields and patch for the scan job
  58. Seal the reply, run fields and patch for the scan job
  59. Fail without a result

### issue-fields

Issue mode only: checks the `run` job's pre-model fields (whether the run started, the reuse and
resume branches, the resume tip and the base SHA) against their closed sets and the combinations
the `run` job's steps make. Any branch claim is re-derived by running `report-outcome.mjs
--find-prior` from the default branch tip, and must match field for field. Every check step is
`continue-on-error`, so the job ends green and a refusal leaves `checked` empty.

- `needs:` `needs: run`
- `if:`

  ```yaml
  if: always() && inputs.issue-number != '' && needs.run.result != 'skipped'
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
  ```

- Steps:
  1. Check the run job's issue fields
  2. Check out the default branch tip
  3. Set up Node
  4. Re-derive the earlier run's work on the issue
  5. Publish the checked issue fields

### scan

On a fresh VM in the `pr-pipeline-scan-carrier` environment, opens the `run` job's sealed payloads
with the scan-carrier private key, holds every `run` job output to its closed set, and scans what
leaves for credentials against a fresh checkout of the commit the patch was made on. After a clean
scan it writes the step summary and is the only job that uploads the reply, patch, review-thread
replies, dependency verdict, issue outcome and verdict artifacts. A handoff skips it.

- `needs:` `needs: [run, issue-fields]`
- `if:`

  ```yaml
  if: >-
    !cancelled() && (needs.run.result == 'success' || needs.run.result == 'failure')
    && needs.run.outputs.handed-off != 'true'
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
  ```

- Steps:
  1. Require the checked issue fields
  2. Assert the default branch is set
  3. Check out the default branch tip
  4. Read the scan-carrier key id
  5. Decode the run job's sealed payloads
  6. Check the run job's outputs and opened payloads
  7. Check out the gated head
  8. Scan the outputs for credentials
  9. Show the skill's run in the step summary
  10. Upload the skill's final reply
  11. Upload the patch
  12. Upload the review-thread replies
  13. Upload the dependency verdict
  14. Upload the issue outcome
  15. Write the verdict
  16. Upload the verdict

### scan-refusal

PR mode only: when the `scan` job failed or was cancelled, writes a marker naming the refusal
(`patch` for an oversize patch, `output` otherwise) and uploads it as an artifact, since a failed
job's outputs may not reach a `workflow_call` caller. The reply and verdict jobs download it by
name.

- `needs:` `needs: scan`
- `if:`

  ```yaml
  if: >-
    always() && inputs.issue-number == ''
    && (needs.scan.result == 'failure' || needs.scan.result == 'cancelled')
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
  ```

- Steps:
  1. Write the scan refusal marker
  2. Upload the scan refusal marker

### summary

Issue mode, reuse only: when `issue-fields` checked a reused lane branch, writes the issue and that
branch's diff from a blobless fetch, then runs a read-only summary pass on `run-claude-cli` whose
one tool is `Read` under `.summary/`. It uploads the structured title, summary and changes as a
`reuse-summary` artifact. Every step is `continue-on-error`, so a failed pass turns nothing red.

- `needs:` `needs: [run, issue-fields]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.issue-fields.outputs.checked == 'true' && needs.issue-fields.outputs.reuse-branch != ''
    && github.event.repository.default_branch != '' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Write the reused branch's diff and issue for the summary pass
  4. Resolve the summary pass's model
  5. Build the summary pass's prompt
  6. Apply the Claude managed settings
  7. Isolate the runner
  8. Summarize the reused branch on the API key
  9. Summarize the reused branch on the OAuth token
  10. Collect the reused branch's summary
  11. Upload the reused branch's summary

### report

PR mode only: from the default branch tip, downloads the verdict, reads the PR's current head, and
chooses the head the check is posted on, posting failure on the trusted head when the `run` job's
head or PR number is forged. It checks the lane's commits are signed when the activity can commit,
then posts the `<lane> / <activity>` check run.

- `needs:` `needs: [broker-check, run, scan]`
- `if:`

  ```yaml
  if: >-
    always() && inputs.issue-number == '' && needs.run.outputs.handed-off != 'true'
    && !(github.event_name == 'pull_request'
    && github.event.pull_request.head.repo.full_name != github.repository)
    && !(github.event_name == 'pull_request'
    && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID)
  ```

- `permissions:`

  ```yaml
  permissions:
    checks: write
    contents: read
    issues: write
    pull-requests: read
  ```

- Steps:
  1. Assert the default branch is set
  2. Check out the default branch tip
  3. Set up Node
  4. Download the verdict
  5. Read the PR's current head SHA
  6. Choose the head the check is posted on
  7. Check the lane's commits are signed
  8. Note that no check is posted without a head SHA
  9. Post the check run

## pr-run-activity-write.yml

### run

Runs one write activity (any effect but `read`) of one lane. From the default branch tip it checks
the kill switch, the trigger, the trusted base and the resolved config, refuses an issue skill or a
review-threads, merge-base or dependency-review skill (those run in the read runner), and for
`apply-patch` downloads, checks and selects the patch before anything is minted. It re-reads the PR
head, requests the effect's App token from the lanes broker, checks out the head, runs the skill on
`claude-code-action` (moving the PR branch to the lane's commits only while it is still at the
gated SHA) or runs the script, writes and uploads the verdict, and revokes the token.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    !(github.event_name == 'pull_request'
    && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID)
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    pull-requests: read
    id-token: write
  ```

- Steps:
  1. Assert the lanes App sender id, default branch and inputs are set
  2. Check out the default branch tip
  3. Set up Node
  4. Check the kill switch
  5. Check the trigger
  6. Assert the base is on the default branch
  7. Resolve the config
  8. Assert an issue skill runs in the read runner
  9. Assert review-threads runs in the read runner
  10. Assert merge-base runs in the read runner
  11. Assert dependency-review runs in the read runner
  12. Check the issue patch's start commit
  13. Check the merge patch's pinned base
  14. Download the patch
  15. Download the model job's report
  16. Download the kept threads
  17. Check the kept threads
  18. Download the dependency verdict for the patch
  19. Check the dependency verdict for the patch
  20. Select the patch
  21. Assert the effect is not read
  22. Re-read the PR head before the mint
  23. Request the lane token
  24. Select the trusted PR text
  25. Stage the activity from the base
  26. Set up Python for the test-file runner
  27. Install the pinned pytest for the test-file runner
  28. Copy the tracker config from the base
  29. Download the review-thread run record
  30. Download the review-thread replies
  31. Download the adjudication verdicts
  32. Download the dependency context
  33. Download the dependency verdict
  34. Download the scan refusal markers
  35. Copy the trusted actors for the reply script
  36. Copy the merge scripts from the base
  37. Read the hold labels from the base
  38. Read the required labels
  39. Copy the apply-patch base files
  40. Isolate the runner
  41. Copy the dependency setup from the base
  42. Check out the PR head
  43. Assert the head is the gated SHA
  44. Start the merge of the pinned base
  45. Make the lane's commit branch at the gated SHA
  46. Set up Python for the skill
  47. Install the skill's dependencies
  48. Run the skill activity
  49. Check the skill's failure is only the turn cap
  50. Show the skill's final reply
  51. Check the skill took a model turn
  52. Name the run's credential
  53. Record the lane outcome
  54. Upload the skill's final reply
  55. Check the gate skill's verdict
  56. Move the PR branch to the lane's commits
  57. Download the issue outcome
  58. Download the reused branch's summary
  59. Run the script activity
  60. Name the issue branch in the outcome
  61. Upload the named issue outcome
  62. Write the verdict
  63. Upload the verdict
  64. Revoke the lane token

### report

PR mode only: from the default branch tip (or the `run` job's base SHA when the default branch
holds it), downloads the verdict, checks the lane's commits are signed, and reads the PR's current
head, reading it up to five times until it matches the branch's `git/ref`. It then posts the `<lane> /
<activity>` check run with the `run` job's result, outcome and lane record.

- `needs:` `needs: run`
- `if:`

  ```yaml
  if: >-
    always() && inputs.issue-number == ''
    && !(github.event_name == 'pull_request'
    && github.event.pull_request.head.repo.full_name != github.repository)
    && !(github.event_name == 'pull_request'
    && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID)
  ```

- `permissions:`

  ```yaml
  permissions:
    checks: write
    contents: read
    issues: write
    pull-requests: read
  ```

- Steps:
  1. Assert the default branch is set
  2. Check out the default branch tip
  3. Check out the run job's base SHA when the default branch holds it
  4. Set up Node
  5. Download the verdict
  6. Check the lane's commits are signed
  7. Read the PR's current head SHA
  8. Note that no check is posted without a head SHA
  9. Post the check run

## pr-run-checks.yml

### check-read-token

Calls `pr-run-activity-read.yml` for the `pr-run-checks` lane's `check-read-token` activity, on a
pull request that touches `sandbox/kill-switch/**` or a dispatch naming a PR. The file stem is the
lane, so the broker's check endpoint accepts it. It passes only the scan-carrier key, no Claude
secret.

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

## pr-unblock-dispatch.yml

### dispatch

On each push to `main`, a half-hourly tick or a hand run, runs `dispatch.mjs` to dispatch
`pr-unblock.yml` for conflicting PRs, review-tier Dependabot PRs and failing lanes App PRs, and
`pr-refine.yml`'s `fix-docs` for Markdown-changing PRs. It holds no model and no App token, honors
the kill switch, and checks a hand run or re-run against the trusted-actor list. It carries a
dispatch record in the Actions cache, uploads an artifact naming every run it dispatched, and logs
the API budget.

- `needs:` none
- `if:`

  ```yaml
  if: github.ref == 'refs/heads/main'
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out main
    pull-requests: read # list open PRs and their mergeable state
    checks: read # skip a PR whose head already has a pr-unblock check run; read ci-status
    actions: write # list and dispatch pr-unblock.yml and pr-refine.yml runs
  ```

- Steps:
  1. Check out the default branch tip
  2. Log the checked-out main tip
  3. Set up Node
  4. Check the kill switch
  5. Report the kill switch
  6. Check the trigger
  7. Stop on an untrusted trigger
  8. Install resolve-config's dependencies
  9. Restore the dispatch record
  10. Dispatch pr-unblock for conflicting, review-tier Dependabot, failing lanes App and Markdown-changing PRs
  11. Save the dispatch record
  12. Name the dispatched-runs record
  13. Record the dispatched runs
  14. Log the API budget at the end

## pr-unblock.yml

### resolve-conflicts-select

Runs only base code with a read-only token: reads the PR head, resolves the `resolve-conflicts`
slot, checks the human-gated hold, pins the default branch tip as the base, and merges it into a
credential-free checkout of the head with the base's `run-prepare.sh`. It decides clean,
conflicted or escalate, and every head, base and conflict tree the later jobs take comes from its
outputs.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    inputs.pr-number != '' && inputs.activity == 'resolve-conflicts'
    && format('{0}', github.event.sender.id) != vars.AUTOMATION_LANES_APP_SENDER_ID
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out main and the PR head
    pull-requests: read # the PR's head and mergeable state
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Check the kill switch
  4. Read the PR head
  5. Resolve the slot
  6. Check the human-gated hold
  7. Pin the base
  8. Copy the merge scripts from the base
  9. Check out the PR head
  10. Merge the base into the head

### resolve-conflicts-not-run

When the select job skipped, merged cleanly or escalated, posts a neutral `resolve-conflicts`
check run on the head it read, so `dispatch.mjs` does not dispatch the PR again. The not-run reason
is the slot's skip reason, else `clean-merge`, else `awaiting-human`.

- `needs:` `needs: resolve-conflicts-select`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && inputs.activity == 'resolve-conflicts'
    && needs.resolve-conflicts-select.outputs.proceed == 'false'
    && needs.resolve-conflicts-select.outputs.head-sha != '' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    checks: write
    contents: read
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Post the resolve-conflicts check run

### resolve-conflicts

The model job: calls `pr-run-activity-read.yml` for `resolve-conflicts` on the pr-unblock role's
API key, passing the select job's head, pinned base and conflict tree. The read runner merges
again, gives the skill the conflicts as read-only files, and hands its resolutions on as a patch.
It runs in the per-PR write queue.

- `needs:` `needs: resolve-conflicts-select`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.resolve-conflicts-select.outputs.proceed == 'true' }}
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

### resolve-conflicts-handoff

Reads from this run's jobs, through `handoff-evidence.sh`, whether the `resolve-conflicts` call's
report job posted its check, never trusting a `resolve-conflicts` output. A failed read leaves
`posted` empty, which starts the fallback call.

- `needs:` `needs: [resolve-conflicts-select, resolve-conflicts]`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.resolve-conflicts-select.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # this run's jobs and their steps
    contents: read # the default branch tip's handoff-evidence.sh
  ```

- Steps:
  1. Check out the default branch tip
  2. Read whether resolve-conflicts posted its check

### resolve-conflicts-subscription

The subscription fallback: calls `pr-run-activity-read.yml` for `resolve-conflicts` again with
`fallback: handoff` on the OAuth token alone, when `resolve-conflicts-handoff` read no check
posted.

- `needs:` `needs: [resolve-conflicts-select, resolve-conflicts, resolve-conflicts-handoff]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.resolve-conflicts-select.outputs.proceed == 'true'
    && needs.resolve-conflicts-handoff.outputs.posted != 'true' }}
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

### apply-conflict-patch

The push job: calls `pr-run-activity-write.yml` for `apply-conflict-patch` under the `merge-base`
row. It merges the pinned base into the head again, applies the answering leg's patch to the
conflict tree, admits only marker-free resolutions, and pushes one merge commit without force; a
clean merge commits with no patch.

- `needs:` `needs: [resolve-conflicts-select, resolve-conflicts, resolve-conflicts-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled()
    && (needs.resolve-conflicts-select.outputs.merge-state == 'clean'
    || needs.resolve-conflicts-select.outputs.proceed == 'true'
    && ((needs.resolve-conflicts-subscription.result != 'skipped' && needs.resolve-conflicts-subscription.outputs.scan-patch-state || needs.resolve-conflicts-subscription.result == 'skipped' && needs.resolve-conflicts.outputs.scan-patch-state || '') == 'written'
    || (needs.resolve-conflicts-subscription.result != 'skipped' && needs.resolve-conflicts-subscription.outputs.scan-patch-state || needs.resolve-conflicts-subscription.result == 'skipped' && needs.resolve-conflicts.outputs.scan-patch-state || '') == 'empty')) }}
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

### conflict-scan-refusal

For a conflicted round whose answering leg handed on no patch state, downloads every attempt's
`resolve-conflicts` scan refusal marker by name and runs `conflict-scan-refusal.mjs`, which
escalates `unresolved-conflict` when a marker says the scan refused. No marker escalates nothing.

- `needs:` `needs: [resolve-conflicts-select, resolve-conflicts, resolve-conflicts-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.resolve-conflicts-select.outputs.proceed == 'true'
    && (needs.resolve-conflicts-subscription.result != 'skipped' && needs.resolve-conflicts-subscription.outputs.scan-patch-state || needs.resolve-conflicts-subscription.result == 'skipped' && needs.resolve-conflicts.outputs.scan-patch-state || '') != 'written'
    && (needs.resolve-conflicts-subscription.result != 'skipped' && needs.resolve-conflicts-subscription.outputs.scan-patch-state || needs.resolve-conflicts-subscription.result == 'skipped' && needs.resolve-conflicts.outputs.scan-patch-state || '') != 'empty' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Download the scan refusal markers
  4. Read the scan refusal

### address-feedback-select

Runs only base code with a read-only token and checks out no PR head: reads the PR head, resolves
the `address-feedback` slot, and keeps the reviewer-bot threads to work on with
`address-feedback.mjs select`. It skips, escalates, or writes and uploads the thread file and
`run.json` the model and reply jobs read.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    inputs.pr-number != '' && inputs.activity == 'address-feedback'
    && format('{0}', github.event.sender.id) != vars.AUTOMATION_LANES_APP_SENDER_ID
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out main
    pull-requests: read # the PR, its reviews, review comments and threads
    checks: read # the model check runs that count rounds
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Check the kill switch
  4. Read the PR head
  5. Resolve the slot
  6. Select the review threads
  7. Upload the feedback context

### address-feedback-not-run

When the select job kept nothing or escalated, posts neutral `address-feedback` and
`publish-feedback` check runs on the head it read, so `feedback-dispatch.mjs` does not dispatch the
PR again.

- `needs:` `needs: address-feedback-select`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && inputs.activity == 'address-feedback'
    && needs.address-feedback-select.outputs.proceed == 'false'
    && needs.address-feedback-select.outputs.head-sha != '' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    checks: write
    contents: read
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Post the address-feedback check run
  4. Post the publish-feedback check run

### address-feedback

The model job: calls `pr-run-activity-read.yml` for `address-feedback` on the pr-unblock role's API
key with the select job's feedback context. The skill fixes the kept threads and records a reply
for each; the runner uploads its edits as a patch and its scanned replies. It runs in the per-PR
write queue.

- `needs:` `needs: address-feedback-select`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.address-feedback-select.outputs.proceed == 'true' }}
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

### address-feedback-handoff

Reads from this run's jobs, through `handoff-evidence.sh`, whether the `address-feedback` call's
report job posted its check. A failed read leaves `posted` empty, which starts the fallback call.

- `needs:` `needs: [address-feedback-select, address-feedback]`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.address-feedback-select.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # this run's jobs and their steps
    contents: read # the default branch tip's handoff-evidence.sh
  ```

- Steps:
  1. Check out the default branch tip
  2. Read whether address-feedback posted its check

### address-feedback-subscription

The subscription fallback: calls `pr-run-activity-read.yml` for `address-feedback` again with
`fallback: handoff` on the OAuth token alone, when `address-feedback-handoff` read no check posted.

- `needs:` `needs: [address-feedback-select, address-feedback, address-feedback-handoff]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.address-feedback-select.outputs.proceed == 'true'
    && needs.address-feedback-handoff.outputs.posted != 'true' }}
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

### apply-feedback-patch

The push job: calls `pr-run-activity-write.yml` for `apply-feedback-patch` under the
`review-threads` row. It admits only paths in the kept threads' scope, skips a head that moved
since the select job read it, and pushes one commit without force. It runs only on a written patch
that came with replies, after `adjudicate-feedback`.

- `needs:`

  ```yaml
  needs: [address-feedback-select, address-feedback, address-feedback-subscription, adjudicate-feedback]
  ```

- `if:`

  ```yaml
  if: >-
    ${{ !cancelled()
    && (needs.address-feedback-subscription.result != 'skipped' && needs.address-feedback-subscription.outputs.scan-patch-state || needs.address-feedback-subscription.result == 'skipped' && needs.address-feedback.outputs.scan-patch-state || '') == 'written'
    && (needs.address-feedback-subscription.result != 'skipped' && needs.address-feedback-subscription.outputs.feedback-attempt || needs.address-feedback-subscription.result == 'skipped' && needs.address-feedback.outputs.feedback-attempt || '') != '' }}
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

### adjudicate-feedback

For up to three INCORRECT replies, runs a fresh-context model per thread on `run-claude-cli` under
`dontAsk` with `Read` alone, confined to that thread's staged slot, and keeps each verdict (lane,
reviewer or human) only when the leg's permission mode checks out. It collects the verdicts and
uploads them as one artifact whose SHA-256 the reply job checks. It runs only base code with a
read-only token and no OIDC token.

- `needs:` `needs: [address-feedback-select, address-feedback, address-feedback-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.address-feedback-select.outputs.proceed == 'true'
    && (needs.address-feedback-subscription.result != 'skipped' && needs.address-feedback-subscription.outputs.feedback-attempt || needs.address-feedback-subscription.result == 'skipped' && needs.address-feedback.outputs.feedback-attempt || '') != '' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # the base checkout and the disputed files at the head
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Check the kill switch
  4. Download the feedback context
  5. Download the review-thread replies
  6. Stage the disputed threads
  7. Resolve the adjudicator's model
  8. Check the API key
  9. Apply the Claude managed settings
  10. Isolate the runner
  11. Stage disputed thread 0
  12. Adjudicate disputed thread 0
  13. Keep disputed thread 0's verdict
  14. Stage disputed thread 1
  15. Adjudicate disputed thread 1
  16. Keep disputed thread 1's verdict
  17. Stage disputed thread 2
  18. Adjudicate disputed thread 2
  19. Keep disputed thread 2's verdict
  20. Collect the verdicts
  21. Upload the verdicts

### publish-feedback

The reply job: calls `pr-run-activity-write.yml` for `publish-feedback` with `review-replies: true`.
The script posts the replies the model job recorded exactly as written, naming the push job's
commit, then the round marker. It runs whenever the select job proceeded, whatever the model and
push jobs did, so every round is counted.

- `needs:`

  ```yaml
  needs: [address-feedback-select, address-feedback, address-feedback-subscription, apply-feedback-patch, adjudicate-feedback]
  ```

- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.address-feedback-select.outputs.proceed == 'true' }}
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

### review-dependency-select

Runs only base code with a read-only token and checks out no PR head: reads the PR head, resolves
the `review-dependency` slot, and selects the PR with `review-dependency.mjs select`. It skips one
Dependabot did not open or one sorted auto, escalates at the round cap, or writes and uploads the
context file and `context.json`.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    inputs.pr-number != '' && inputs.activity == 'review-dependency'
    && format('{0}', github.event.sender.id) != vars.AUTOMATION_LANES_APP_SENDER_ID
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out main
    pull-requests: read # the PR, its commits and files
    checks: read # ci-status and the model check runs that count rounds
    issues: read # the round markers
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Check the kill switch
  4. Read the PR head
  5. Resolve the slot
  6. Select the dependency pull request
  7. Upload the dependency context

### review-dependency-not-run

When the select job skipped or escalated, posts a neutral `review-dependency` check run on the head
it read, so `dependency-dispatch.mjs` does not dispatch the PR again.

- `needs:` `needs: review-dependency-select`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && inputs.activity == 'review-dependency'
    && needs.review-dependency-select.outputs.proceed == 'false'
    && needs.review-dependency-select.outputs.head-sha != '' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    checks: write
    contents: read
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Post the review-dependency check run

### review-dependency

The model job: calls `pr-run-activity-read.yml` for `review-dependency` on the pr-unblock role's
API key with the select job's dependency context. The skill reviews the update and returns its
verdict as structured output; a fix leaves the change uncommitted for the runner to hand on as a
patch. It runs in the per-PR write queue.

- `needs:` `needs: review-dependency-select`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.review-dependency-select.outputs.proceed == 'true' }}
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

### review-dependency-handoff

Reads from this run's jobs, through `handoff-evidence.sh`, whether the `review-dependency` call's
report job posted its check. A failed read leaves `posted` empty, which starts the fallback call.

- `needs:` `needs: [review-dependency-select, review-dependency]`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.review-dependency-select.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # this run's jobs and their steps
    contents: read # the default branch tip's handoff-evidence.sh
  ```

- Steps:
  1. Check out the default branch tip
  2. Read whether review-dependency posted its check

### review-dependency-subscription

The subscription fallback: calls `pr-run-activity-read.yml` for `review-dependency` again with
`fallback: handoff` on the OAuth token alone, when `review-dependency-handoff` read no check
posted.

- `needs:` `needs: [review-dependency-select, review-dependency, review-dependency-handoff]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.review-dependency-select.outputs.proceed == 'true'
    && needs.review-dependency-handoff.outputs.posted != 'true' }}
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

### apply-dependency-patch

The push job: calls `pr-run-activity-write.yml` for `apply-dependency-patch` under the
`dependency-review` row. It admits only a version change of npm or pip manifest and lock files in a
directory the base `dependabot.yml` lists, and pushes one `[dependabot skip]` commit without force.
It runs only on a written patch beside a scanned `fix` verdict.

- `needs:` `needs: [review-dependency-select, review-dependency, review-dependency-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled()
    && (needs.review-dependency-subscription.result != 'skipped' && needs.review-dependency-subscription.outputs.scan-patch-state || needs.review-dependency-subscription.result == 'skipped' && needs.review-dependency.outputs.scan-patch-state || '') == 'written'
    && (needs.review-dependency-subscription.result != 'skipped' && needs.review-dependency-subscription.outputs.dependency-verdict || needs.review-dependency-subscription.result == 'skipped' && needs.review-dependency.outputs.dependency-verdict || '') == 'fix' }}
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

### apply-dependency-verdict

The verdict job: calls `pr-run-activity-write.yml` for `apply-dependency-verdict` with
`dependency-verdict: true`. The script acts on the verdict: the round marker, a close (never of a
security update) with an ignore-entry issue, or an escalation. It runs whenever the select job
proceeded, so every round is counted, and it never merges.

- `needs:`

  ```yaml
  needs: [review-dependency-select, review-dependency, review-dependency-subscription, apply-dependency-patch]
  ```

- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.review-dependency-select.outputs.proceed == 'true' }}
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

Runs only base code with a read-only token and checks out no PR head: `fix-ci-context.mjs` escalates
once `loop.fix-ci-rounds` fixes were pushed, or writes the failing checks' names, workflows,
annotations and log ends to a context file. It uploads that file for the model job, and its outputs
carry the gated head, the context's SHA-256 and attempt, and any skip or escalation.

- `needs:` none
- `if:`

  ```yaml
  if: >-
    inputs.pr-number != '' && inputs.activity == 'fix-ci'
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

### fix-ci-not-run

When `fix-ci-context` skipped without escalating (a closed PR, a human-gated hold, or no failing
check), posts a neutral `fix-ci` check run on its head, so `fix-ci-dispatch.mjs` does not dispatch
the PR again.

- `needs:` `needs: fix-ci-context`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && inputs.activity == 'fix-ci'
    && needs.fix-ci-context.outputs.proceed == 'false'
    && needs.fix-ci-context.outputs.escalation-reason == ''
    && needs.fix-ci-context.outputs.head-sha != '' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    checks: write
    contents: read
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Post the check run

### fix-ci

The model job: calls `pr-run-activity-read.yml` for `fix-ci` on the pr-unblock role's API key with
the CI context. The skill reruns the failing checks, fixes them and reruns them, and the runner
uploads its edits as a patch. It runs in the per-PR write queue.

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

### fix-ci-handoff

Reads from this run's jobs, through `handoff-evidence.sh`, whether the `fix-ci` call's report job
posted its check, never trusting `fix-ci`'s forgeable outputs. A failed read leaves `posted` empty,
which starts the fallback call.

- `needs:` `needs: [fix-ci-context, fix-ci]`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # this run's jobs and their steps
    contents: read # the default branch tip's handoff-evidence.sh
  ```

- Steps:
  1. Check out the default branch tip
  2. Read whether fix-ci posted its check

### fix-ci-subscription

The subscription fallback: calls `pr-run-activity-read.yml` for `fix-ci` again with
`fallback: handoff` on the OAuth token alone, when `fix-ci-handoff` read no check posted.

- `needs:` `needs: [fix-ci-context, fix-ci, fix-ci-handoff]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true'
    && needs.fix-ci-handoff.outputs.posted != 'true' }}
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

The push job: calls `pr-run-activity-write.yml` for `apply-patch` under the `ci-context` row with
the answering leg's scan outputs and the head `fix-ci-context` gated. It applies the patch, refuses
what the row refuses, and pushes one commit without force; an empty or refused patch or an escalated
check hands the PR to a person, or skips `rung-up` for one retry.

- `needs:` `needs: [fix-ci-context, fix-ci, fix-ci-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled()
    && ((needs.fix-ci-subscription.result != 'skipped' && needs.fix-ci-subscription.outputs.scan-patch-state || needs.fix-ci-subscription.result == 'skipped' && needs.fix-ci.outputs.scan-patch-state || '') == 'written'
    || (needs.fix-ci-subscription.result != 'skipped' && needs.fix-ci-subscription.outputs.scan-patch-state || needs.fix-ci-subscription.result == 'skipped' && needs.fix-ci.outputs.scan-patch-state || '') == 'empty'
    || (needs.fix-ci-subscription.result != 'skipped' && needs.fix-ci-subscription.outputs.scan-collect-refused || needs.fix-ci-subscription.result == 'skipped' && needs.fix-ci.outputs.scan-collect-refused || '') == 'true') }}
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

### fix-ci-rung-up

`fix-ci`'s one retry one model rung up: when `apply-patch` skipped `rung-up`, calls
`pr-run-activity-read.yml` for `fix-ci` again at `model-rung: "1"` on the same context and head,
on the API key.

- `needs:` `needs: [fix-ci-context, apply-patch]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true'
    && needs.apply-patch.outputs.rung-up == 'true' }}
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

### fix-ci-rung-up-handoff

As `fix-ci-handoff` is for `fix-ci`: reads from this run's jobs whether the `fix-ci-rung-up` call
posted its check.

- `needs:` `needs: [fix-ci-context, fix-ci-rung-up]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true'
    && needs.fix-ci-rung-up.result != 'skipped' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # this run's jobs and their steps
    contents: read # the default branch tip's handoff-evidence.sh
  ```

- Steps:
  1. Check out the default branch tip
  2. Read whether fix-ci-rung-up posted its check

### fix-ci-rung-up-subscription

The rung-up retry's subscription fallback: calls `pr-run-activity-read.yml` for `fix-ci` at
`model-rung: "1"` with `fallback: handoff` on the OAuth token, when `fix-ci-rung-up-handoff` read
no check posted.

- `needs:` `needs: [fix-ci-context, fix-ci-rung-up, fix-ci-rung-up-handoff]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true'
    && needs.fix-ci-rung-up.result != 'skipped'
    && needs.fix-ci-rung-up-handoff.outputs.posted != 'true' }}
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

### apply-patch-rung-up

The rung-up retry's push job: calls `pr-run-activity-write.yml` for `apply-patch` under the
`ci-context` row at `patch-model-rung: "1"`, where an escalation goes to a person since there is no
rung above.

- `needs:` `needs: [fix-ci-context, fix-ci-rung-up, fix-ci-rung-up-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled()
    && ((needs.fix-ci-rung-up-subscription.result != 'skipped' && needs.fix-ci-rung-up-subscription.outputs.scan-patch-state || needs.fix-ci-rung-up-subscription.result == 'skipped' && needs.fix-ci-rung-up.outputs.scan-patch-state || '') == 'written'
    || (needs.fix-ci-rung-up-subscription.result != 'skipped' && needs.fix-ci-rung-up-subscription.outputs.scan-patch-state || needs.fix-ci-rung-up-subscription.result == 'skipped' && needs.fix-ci-rung-up.outputs.scan-patch-state || '') == 'empty'
    || (needs.fix-ci-rung-up-subscription.result != 'skipped' && needs.fix-ci-rung-up-subscription.outputs.scan-collect-refused || needs.fix-ci-rung-up-subscription.result == 'skipped' && needs.fix-ci-rung-up.outputs.scan-collect-refused || '') == 'true') }}
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

### fix-ci-unreported

When no `fix-ci` call posted a check, reads this run's jobs through `handoff-evidence.sh` and posts
`fix-ci` failure on the gated head, so `fix-ci-dispatch.mjs` counts the round. It posts nothing
unless a call's `broker-check` job allowed the lane.

- `needs:`

  ```yaml
  needs: [fix-ci-context, fix-ci, fix-ci-subscription, fix-ci-rung-up, fix-ci-rung-up-subscription]
  ```

- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.fix-ci-context.outputs.proceed == 'true' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # this run's jobs and their steps
    checks: write
    contents: read
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Read whether a fix-ci call posted its check
  4. Post the check run

### report-conflict-status

When the select job, the push job or the scan refusal escalated `unresolved-conflict`, posts a
failing `pr-unblock/conflict` commit status on the select job's head with
`report-escalation.sh status`. It is the lane's only `statuses: write`, on its own `GITHUB_TOKEN`.

- `needs:` `needs: [resolve-conflicts-select, apply-conflict-patch, conflict-scan-refusal]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && needs.resolve-conflicts-select.outputs.head-sha != ''
    && (needs.resolve-conflicts-select.outputs.escalation-reason == 'unresolved-conflict'
    || needs.apply-conflict-patch.outputs.escalation-reason == 'unresolved-conflict'
    || needs.conflict-scan-refusal.outputs.escalation-reason == 'unresolved-conflict') }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    statuses: write
  ```

- Steps:
  1. Check out the default branch tip
  2. Post the conflict status

### report-escalation

Calls `pr-run-activity-write.yml` for `report-escalation` with the first escalation reason any
select, push, reply, verdict or scan-refusal job set, or `ci-fix-escalated` for a rung-up retry
whose patch did not apply cleanly. At most one activity escalates per dispatch.

- `needs:`

  ```yaml
  needs:
    - resolve-conflicts-select
    - apply-conflict-patch
    - conflict-scan-refusal
    - address-feedback-select
    - publish-feedback
    - review-dependency-select
    - apply-dependency-verdict
    - fix-ci-context
    - apply-patch
    - apply-patch-rung-up
  ```

- `if:`

  ```yaml
  if: >-
    ${{ (!cancelled() && (needs.resolve-conflicts-select.outputs.escalation-reason != ''
    || needs.apply-conflict-patch.outputs.escalation-reason != ''
    || needs.conflict-scan-refusal.outputs.escalation-reason != ''
    || needs.address-feedback-select.outputs.escalation-reason != ''
    || needs.publish-feedback.outputs.escalation-reason != ''
    || needs.review-dependency-select.outputs.escalation-reason != ''
    || needs.apply-dependency-verdict.outputs.escalation-reason != ''
    || needs.fix-ci-context.outputs.escalation-reason != ''
    || needs.apply-patch.outputs.escalation-reason != ''))
    || (always() && needs.apply-patch.outputs.rung-up == 'true'
    && !(needs.apply-patch-rung-up.result == 'success'
    && needs.apply-patch-rung-up.outputs.escalation-reason == ''
    && needs.apply-patch-rung-up.outputs.patch-skip-reason == '')) }}
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

## rate-probe.yml

### read

A hand-dispatched probe that logs the repository `GITHUB_TOKEN`'s core rate-limit use (used, limit,
remaining and reset) from `GET /rate_limit`, which does not count against the limit. It is read
before and after a dispatcher push.

- `needs:` none
- `if:` none
- `permissions:` `permissions: {}`
- Steps:
  1. Log core rate-limit use

## work-resolve-issue.yml

### admit

The lane's admission gate, before any job that gets a credential: from the default branch tip, with
a read-only token and no secret, it runs `check-trusted-trigger` so that only a listed human, or
the lanes App applying `agent-ready` itself, starts the lane. Its `proceed` output gates every
later job.

- `needs:` none
- `if:`

  ```yaml
  if: github.event.label.name == 'agent-ready'
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
  ```

- Steps:
  1. Assert the lanes App sender id and default branch are set
  2. Check out the default branch tip
  3. Set up Node
  4. Check the trigger

### pick-slot

Checks the WIP cap, resolves the run job's timeout and issue dimensions from the issue's Size,
Complexity and Uncertainty fields through the base config, and picks the concurrency slot as the
issue number modulo `SLOTS` (3). Its outputs carry the slot, whether the WIP cap paused the lane,
the timeout, the dimensions and any dimension skip reason.

- `needs:` `needs: admit`
- `if:`

  ```yaml
  if: github.event.label.name == 'agent-ready' && needs.admit.outputs.proceed == 'true'
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read # check out the default branch for the WIP cap
    pull-requests: read # count the lanes App's open pull requests
    issues: read # read the issue's Size, Complexity and Uncertainty fields
  ```

- Steps:
  1. Check out the default branch tip
  2. Check the WIP cap
  3. Resolve the issue dimensions' timeout
  4. Pick the slot

### resolve-issue

Calls `pr-run-activity-read.yml` for the `resolve-issue` activity in issue mode on the issue lane's
API key, in the picked slot's queue. The skill runs `/work-items:work` on the issue with no write
token and leaves its change as a patch, or stops and says why.

- `needs:` `needs: [admit, pick-slot]`
- `if:`

  ```yaml
  if: >-
    github.event.label.name == 'agent-ready' && needs.admit.outputs.proceed == 'true'
    && needs.pick-slot.outputs.capped != 'true'
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

### resolve-issue-handoff

Reads from this run's jobs, through `handoff-evidence.sh`, whether the `resolve-issue` call handed
off (its broker-allowed and run jobs succeeded and its scan job never ran), never trusting a
`resolve-issue` output. A failed read fails this job and starts no second call.

- `needs:` `needs: resolve-issue`
- `if:`

  ```yaml
  if: ${{ !cancelled() && needs.resolve-issue.result != 'skipped' }}
  ```

- `permissions:`

  ```yaml
  permissions:
    actions: read # this run's jobs and their steps
    contents: read # the default branch tip's handoff-evidence.sh
  ```

- Steps:
  1. Check out the default branch tip
  2. Read whether resolve-issue handed off

### resolve-issue-subscription

The subscription fallback: calls `pr-run-activity-read.yml` for `resolve-issue` again with
`fallback: handoff` on the OAuth token alone, in the same slot, when `resolve-issue-handoff` read a
handoff.

- `needs:` `needs: [admit, pick-slot, resolve-issue, resolve-issue-handoff]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && github.event.label.name == 'agent-ready' && needs.admit.outputs.proceed == 'true'
    && needs.pick-slot.outputs.capped != 'true' && needs.resolve-issue-handoff.outputs.handed-off == 'true' }}
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

### report-skip

For an issue its dimensions skip (`split-required`, `research-first` or `probe-first`), calls
`pr-run-activity-write.yml`'s `report-outcome` with `dimension-skip`, which labels the issue
`needs-human`, removes `agent-ready` and comments the next step. It needs no slot.

- `needs:` `needs: [admit, pick-slot]`
- `if:`

  ```yaml
  if: >-
    github.event.label.name == 'agent-ready' && needs.admit.outputs.proceed == 'true'
    && (needs.pick-slot.outputs.skip-reason == 'split-required'
    || needs.pick-slot.outputs.skip-reason == 'research-first'
    || needs.pick-slot.outputs.skip-reason == 'probe-first')
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

### apply-issue-patch

The commit job: calls `pr-run-activity-write.yml` for `apply-issue-patch` with the answering leg's
scan outputs. The script checks the patch's SHA-256, applies it to the commit the model worked on,
refuses the paths the `issue` row refuses, re-reads the hold labels and `agent-ready`, and commits
to a new `work-resolve-issue/issue-<n>-<run id>-<attempt>` branch. One runs per issue at a time.

- `needs:` `needs: [resolve-issue, resolve-issue-subscription]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && (needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-issue-run-started || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-issue-run-started || '') == 'true'
    && (needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-patch-state || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-patch-state || '') == 'written' }}
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

### report-statuses

Posts one `pipeline/<activity>` commit status per lane step on the lane branch's head with
`post-statuses.mjs`, from the issue outcome and the job results. It is the lane's only
`statuses: write` grant, on the job's own `GITHUB_TOKEN`, and runs only default-branch-tip
scripts.

- `needs:` `needs: [resolve-issue, resolve-issue-subscription, apply-issue-patch, run-checks, report-outcome]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && ((needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-issue-run-started || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-issue-run-started || '') == 'true'
    || (needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-reuse-branch || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-reuse-branch || '') != '') }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    statuses: write
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Download the issue outcome
  4. Post the pipeline statuses

### run-checks

Runs the `resolve-issue` activity's configured `checks` itself, on a fresh runner no model ran on,
since the model's outcome file is only its own word. It checks out the lane branch, replaces its
`scripts/` with the base's (restoring the branch's own data files), runs each check, and publishes
the results with the tip they checked as its `checks` output.

- `needs:` `needs: [resolve-issue, resolve-issue-subscription, apply-issue-patch]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && ((needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-issue-run-started || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-issue-run-started || '') == 'true'
    && (needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-outcome-uploaded || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-outcome-uploaded || '') == 'true'
    || (needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-reuse-branch || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-reuse-branch || '') != '') }}
  ```

- `permissions:`

  ```yaml
  permissions:
    contents: read
    issues: read # resolve-config reads the issue's labels for labels-absent
  ```

- Steps:
  1. Check out the default branch tip
  2. Set up Node
  3. Resolve the config
  4. Download the issue outcome
  5. Pick the lane branch
  6. Check out the lane branch
  7. Run the activity's checks

### report-outcome

Calls `pr-run-activity-write.yml`'s `report-outcome`, which opens a ready PR from the lane branch
(or the reused branch), or comments on the issue and labels it `needs-human`. It passes the reuse
branch, the `run-checks` results only when that job succeeded, and `apply-issue-patch`'s escalation
reason.

- `needs:` `needs: [resolve-issue, resolve-issue-subscription, apply-issue-patch, run-checks]`
- `if:`

  ```yaml
  if: >-
    ${{ !cancelled() && ((needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-issue-run-started || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-issue-run-started || '') == 'true'
    || (needs.resolve-issue-subscription.result != 'skipped' && needs.resolve-issue-subscription.outputs.scan-reuse-branch || needs.resolve-issue-subscription.result == 'skipped' && needs.resolve-issue.outputs.scan-reuse-branch || '') != '') }}
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
