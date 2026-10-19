#!/usr/bin/env bash
# Phase 0b probe: record that a plugin hook or MCP server started. Writes only
# the kind and the time, never any environment value.
kind="${1:-unknown}"
for dir in "${RUNNER_TEMP:-}" /tmp; do
  [ -n "$dir" ] && date -u +%Y-%m-%dT%H:%M:%SZ >"$dir/probe-0b-$kind-fired" 2>/dev/null
done
exit 0
