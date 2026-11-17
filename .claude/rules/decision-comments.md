---
description: "Review flags a deleted comment that held the only record of why a decision was made"
paths:
  - "**/*.mjs"
  - "**/*.js"
  - "**/*.ts"
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.py"
  - "**/*.ps1"
  - "**/*.awk"
  - "**/*.html"
  - "**/*.yml"
  - "**/*.yaml"
---

# Deleted decision comments

A deleted comment that recorded why one of the repository's own decisions was made is flagged
when that reason is in no ADR, commit message, or linked source: move the reason into an ADR or
the commit message, or keep the comment. A comment that only restates code or notes history is
not such a record.
