# Workflow triggers

| Workflow file | Triggers |
| --- | --- |
| pr-refine.yml | pull_request, workflow_dispatch |
| pr-require-checks.yml | pull_request, merge_group |
| pr-review-hosted.yml | pull_request |
| pr-review-no-bots.yml | pull_request |
| pr-review-security-hosted.yml | pull_request |
| pr-run-activity-probe.yml | pull_request, workflow_dispatch |
| pr-run-activity-read-probe.yml | pull_request, workflow_dispatch |
| pr-run-activity-read.yml | workflow_call |
| pr-run-activity-write.yml | workflow_call |
| pr-run-checks.yml | pull_request, workflow_dispatch |
| pr-unblock-dispatch.yml | push, workflow_dispatch |
| pr-unblock.yml | workflow_dispatch |
| rate-probe.yml | workflow_dispatch |
| work-resolve-issue.yml | issues |
