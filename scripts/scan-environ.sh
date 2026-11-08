#!/usr/bin/env bash
# scan-environ.sh: report which visible processes hold a non-empty GH_TOKEN or
# GITHUB_TOKEN, as checkout code a verify-script wrapper runs would see them.
# Prints pids, process names and key names, never a value. A child started with
# a fake token is the positive control. Exit 1 when the control is not found or
# another process holds a token.
set -u

GH_TOKEN=scan-environ-control-marker sleep 30 &
control=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(cat "/proc/$control/comm" 2>/dev/null)" = sleep ] && break
  sleep 0.1
done

seen=0
unreadable=0
control_found=0
leaks=0
for f in /proc/[0-9]*/environ; do
  d=${f%/environ}
  pid=${d#/proc/}
  [ -r "$f" ] || {
    unreadable=$((unreadable + 1))
    continue
  }
  seen=$((seen + 1))
  keys=$(tr '\0' '\n' <"$f" 2>/dev/null | grep -Eo '^(GH_TOKEN|GITHUB_TOKEN)=.' | cut -d= -f1 | tr '\n' ' ')
  [ -n "$keys" ] || continue
  if [ "$pid" = "$control" ]; then
    control_found=1
    echo "control $pid $(cat "$d/comm" 2>/dev/null): $keys"
  else
    leaks=$((leaks + 1))
    echo "holder $pid $(cat "$d/comm" 2>/dev/null): $keys"
  fi
done
kill "$control" 2>/dev/null

echo "pid 1: $(cat /proc/1/comm 2>/dev/null)"
echo "own GH_TOKEN set: ${GH_TOKEN+yes}, own GITHUB_TOKEN set: ${GITHUB_TOKEN+yes}"
echo "processes read: $seen, unreadable: $unreadable"
echo "origin URL carries a credential: $(git config --get remote.origin.url | grep -c 'x-access-token:')"
echo "control found: $control_found, other holders: $leaks"
[ "$control_found" = 1 ] && [ "$leaks" = 0 ]
