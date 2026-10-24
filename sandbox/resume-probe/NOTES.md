# Workflow triggers

- `pr-check-managed-files.yml`: starts on a `pull_request` into `main` and on a `merge_group` `checks_requested` event.
- `pr-feedback-dispatch.yml`: starts on `workflow_run` when a `pr-review-hosted` or `pr-review-security-hosted` run is `completed`.
- `pr-merge.yml`: starts on `workflow_run` when a `pr-require-checks`, `pr-review-hosted` or `pr-review-security-hosted` run is `completed`, on `pull_request_target` `labeled`, `unlabeled`, `edited` and `ready_for_review`, on `workflow_dispatch`, and on the hourly `schedule` cron `41 * * * *`.
- `pr-refine.yml`: starts on `pull_request` `opened`, `synchronize` and `reopened`, and on `workflow_dispatch` with a `pr-number` and an `activity` input.
- `pr-require-checks.yml`: starts on a `pull_request` into `main` that is `opened`, `synchronize`, `reopened`, `ready_for_review`, `labeled` or `unlabeled`, on a `merge_group` `checks_requested` event, and on `workflow_dispatch`.
- `pr-review-hosted.yml`: starts on `pull_request` `opened`, `synchronize`, `ready_for_review` and `reopened`.
- `pr-review-no-bots.yml`: starts on `pull_request` `opened`, `synchronize`, `ready_for_review` and `reopened`.
- `pr-review-security-hosted.yml`: starts on `pull_request` `opened`, `synchronize`, `ready_for_review` and `reopened`.
- `pr-run-activity-read-probe.yml`: starts on `pull_request` `opened`, `synchronize` and `reopened` that touches `sandbox/read-split/**`, and on `workflow_dispatch` with a `pr-number` input.
- `pr-run-activity-read.yml`: starts only through `workflow_call`, as a reusable workflow another workflow calls.
- `pr-run-activity-write.yml`: starts only through `workflow_call`, as a reusable workflow another workflow calls.
- `pr-run-checks.yml`: starts on `pull_request` `opened`, `synchronize` and `reopened` that touches `sandbox/kill-switch/**`, and on `workflow_dispatch` with a `pr-number` input.
- `pr-unblock-dispatch.yml`: starts on a `push` to `main`, on the `schedule` cron `9,39 * * * *`, and on `workflow_dispatch`.
- `pr-unblock.yml`: starts only on `workflow_dispatch`, with a `pr-number`, an `activity` and a `dispatcher-run-id` input.
- `rate-probe.yml`: starts only on `workflow_dispatch`.
- `work-resolve-issue.yml`: starts on an `issues` `labeled` event.
