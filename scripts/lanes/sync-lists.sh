# sync-lists.sh: the paths this sandbox copies from claude-code-plugins.
# check-sync.sh and resync.sh source it; neither keeps its own copy.
#
# SYNCED: copied byte-for-byte. LEFT_OUT: upstream paths under a SYNCED path
# this sandbox does not carry. ADAPTED: this sandbox's own versions. PINNED:
# compared against their own claude-code-plugins commit instead of the ref.
# shellcheck shell=bash disable=SC2034  # the sourcing script reads the lists

SYNCED=(
  .github/actions/check-born-triaged
  .github/actions/check-kill-switch
  .github/actions/check-signed-commits
  .github/actions/check-trusted-base
  .github/actions/check-trusted-trigger
  .github/actions/check-wip-cap
  .github/actions/check-upstream-status
  .github/actions/collect-base-activity
  .github/actions/log-api-budget
  .github/actions/open-lane-output
  .github/actions/report-check-run
  .github/actions/request-lane-token
  .github/actions/resolve-config
  .github/actions/seal-lane-output
  .github/actions/select-trusted-text
  .github/actions/setup-runner-isolation
  .github/actions/upload-fail-index
  .github/artifact-retention.json
  .github/lane-keys
  .github/scripts/apply-patch
  .github/scripts/lib
  .github/scripts/merge-base
  .github/scripts/plugin-eval/eval-handoff.mjs
  .github/scripts/pr-merge
  .github/scripts/pr-unblock
  .github/scripts/pr-verify
  .github/scripts/read-patch
  .github/scripts/work-resolve-issue
  # Modules the synced scripts and tests import from outside those folders.
  .github/recurring-schedule.json
  .github/requirements-relock.txt
  .github/lane-registry.json
  .github/scripts/intake-triage/admit.mjs
  .github/scripts/intake-triage/issue-spec.mjs
  .github/scripts/intake-triage/size-split.mjs
  .github/scripts/lane-run-report/post.mjs
  .github/scripts/maintenance-monitor-signals/issues.mjs
  .github/scripts/maintenance-reconcile-lost-runs/component-status.mjs
  .github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs
  .github/scripts/pr-dispatch-feedback/rerun-ci-status.sh
  .github/scripts/pr-review-main/write-verdict.mjs
  .github/scripts/recurring-schedule/file-due.mjs
  # The source-control trust settings the synced workflows' drop-in step
  # reads from the base; without it that step fails.
  .github/source-control-settings.json
  .github/workflows/pr-dispatch-feedback.yml
  .github/workflows/pr-merge.yml
  .github/workflows/pr-run-activity-read.yml
  .github/workflows/pr-run-activity-write.yml
  .github/workflows/pr-unblock-dispatch.yml
  .github/workflows/pr-unblock.yml
  .github/workflows/pr-verify.yml
  .github/workflows/work-resolve-issue.yml
  docs/conventions/pr-pipeline/examples
  docs/conventions/pr-pipeline/pr-pipeline.schema.json
  # What the read runner's skill setup, leak scan and role routes read from
  # the base.
  .github/requirements-ci.txt
  .github/npm-fetch.npmrc
  .python-version
  lib/publish-gate.mjs
  lib/test-tmp.mjs
  package-lock.json
  package.json
  plugins/multi-agent/reference/defaults.yaml
  scripts/ci-deps
  # Whole plugins: the babysit-prs scripts, the work-item tracker, the issue
  # lane's skill, the research/doc skills (discovery, knowledge) and the
  # fix-docs audit skill (ai-slop), with everything they read inside their
  # plugin.
  plugins/ai-slop
  plugins/discovery
  plugins/knowledge
  plugins/source-control
  plugins/work-items
  scripts/setup-env.sh
  # The read runner's caller-secret gate, and the shadow check the owner runs
  # after the scan-carrier keygen.
  scripts/check-read-caller-keys.mjs
  scripts/check-read-caller-keys.sh
  scripts/check-scan-carrier-secret-shadow.sh
  # resolve-issue's self-check and verify-script, staged as .lane wrappers.
  # check-affected.sh skips each check whose script or tool is not here.
  scripts/check-affected.sh
  scripts/git-mv-rm.sh
  scripts/lib/checkout-path.sh
  # check-affected.sh reads the standards org layer (lint configs) through it.
  lib/org-standards.sh
  # The transcript metrics resolve-config's callers.test.mjs imports.
  scripts/lane-transcripts/store.mjs
)

# Upstream paths under a SYNCED path this sandbox leaves out. pr-verify's probe
# fixtures hold a fake AWS key the secret scan refuses; no workflow reads them.
LEFT_OUT=(
  .github/scripts/pr-verify/probe
  # Reads generated docs and other plugins' fixtures this sandbox does not carry.
  plugins/ai-slop/skills/audit/scripts/generated-docs-regions.test.sh
  # These read SKILL.md files of plugins this sandbox does not carry.
  plugins/work-items/skills/work/unattended-callers.test.mjs
  plugins/work-items/skills/work/unattended-callers.test.sh
)

# The sandbox's own versions of files claude-code-plugins also has.
ADAPTED=(
  # Sandbox activities and lanes, migrated to schema version 2.
  # review-dependency, apply-dependency-verdict, fix-ci and apply-ci-fix are
  # main's, unchanged; resolve-issue takes main's labels and holds but keeps
  # no checks.
  docs/conventions/pr-pipeline.yaml
  # Sandbox activity fix-marker and its patch job, with the role input,
  # and the fix-ci fallback probe (pr-unblock.yml's fix-ci jobs on this lane).
  # Its run-name, dispatcher-run-id input and fix-docs jobs are main's on the
  # automations role: sync them with the dispatcher, which sends that input.
  .github/workflows/pr-refine.yml
  # The sandbox's own scan-carrier key pair: one per repository, never shared.
  # Until the owner runs keygen here it is the placeholder line, so seal fails
  # closed.
  .github/lane-keys/scan-carrier.pub
)

# "<path> <commit>": compared against that commit instead of the ref.
PINNED=()
