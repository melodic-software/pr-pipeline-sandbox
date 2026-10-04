#!/usr/bin/env bash
# A read activity runs after "Remove sudo and docker access": sudo, the docker
# socket and `docker info` must all fail. Exits 0 only when every one fails.
# Also reports, without failing on it, whether this process can read the
# Runner.Worker process's memory; it prints byte counts only, never contents.
set -uo pipefail

open=0

echo "== sudo -n true"
if sudo -n true; then
  echo "RESULT sudo: works"
  open=1
else
  echo "RESULT sudo: fails (exit $?)"
fi

sock=/var/run/docker.sock
echo "== docker socket"
ls -l "$sock" || true
if [ -r "$sock" ]; then
  echo "RESULT socket readable: yes"
  open=1
else
  echo "RESULT socket readable: no"
fi
if [ -w "$sock" ]; then
  echo "RESULT socket writable: yes"
  open=1
else
  echo "RESULT socket writable: no"
fi

echo "== docker info"
if docker info >/dev/null 2>"$RUNNER_TEMP/docker-info.err"; then
  echo "RESULT docker info: works"
  open=1
else
  echo "RESULT docker info: fails"
  head -n 3 "$RUNNER_TEMP/docker-info.err"
fi

echo "== /proc/<Runner.Worker pid>/mem (observation only)"
echo "ptrace_scope: $(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo unknown)"
pid=$(pgrep -f 'Runner.Worker' | head -n 1 || true)
if [ -z "$pid" ]; then
  echo "RESULT runner mem: no Runner.Worker process found"
else
  echo "Runner.Worker pid $pid, owner $(stat -c %U "/proc/$pid")"
  python3 - "$pid" <<'PY'
import sys

pid = sys.argv[1]
try:
    with open(f"/proc/{pid}/maps") as maps:
        regions = [line.split() for line in maps]
except OSError as error:
    print(f"RESULT runner mem: maps unreadable ({error.__class__.__name__}: {error.strerror})")
    sys.exit(0)
print(f"maps readable: {len(regions)} regions")
total = 0
errors = set()
try:
    mem = open(f"/proc/{pid}/mem", "rb", 0)
except OSError as error:
    print(f"RESULT runner mem: open failed ({error.__class__.__name__}: {error.strerror})")
    sys.exit(0)
for fields in regions:
    if "r" not in fields[1]:
        continue
    start = int(fields[0].split("-")[0], 16)
    try:
        mem.seek(start)
        total += len(mem.read(4096))
    except OSError as error:
        errors.add(f"{error.__class__.__name__}: {error.strerror}")
    if total >= 65536:
        break
print(f"RESULT runner mem: read {total} bytes; errors: {sorted(errors) or 'none'}")
PY
fi

if [ "$open" -ne 0 ]; then
  echo "::error::sudo or docker is still reachable from a read activity"
  exit 1
fi
echo "check-hardening: sudo and docker are closed"
