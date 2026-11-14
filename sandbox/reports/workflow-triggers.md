# Workflow triggers

| Workflow file | Triggers |
| --- | --- |
| maintenance-delete-stale-branches.yml | schedule, workflow_dispatch |
| pr-check-managed-files-hosted.yml | pull_request |
| pr-check-managed-files.yml | pull_request, merge_group |
| pr-feedback-dispatch.yml | workflow_run |
| pr-merge.yml | workflow_run, pull_request_target, workflow_dispatch, schedule |
| pr-refine.yml | pull_request, workflow_dispatch |
| pr-require-checks.yml | pull_request, merge_group, workflow_dispatch |
| pr-review-hosted.yml | pull_request |
| pr-review-no-bots.yml | pull_request |
| pr-review-security-hosted.yml | pull_request |
| pr-run-activity-read-probe.yml | pull_request, workflow_dispatch |
| pr-run-activity-read.yml | workflow_call |
| pr-run-activity-write.yml | workflow_call |
| pr-run-checks.yml | pull_request, workflow_dispatch |
| pr-unblock-dispatch.yml | push, schedule, workflow_dispatch |
| pr-unblock.yml | workflow_dispatch |
| work-resolve-issue.yml | issues |
