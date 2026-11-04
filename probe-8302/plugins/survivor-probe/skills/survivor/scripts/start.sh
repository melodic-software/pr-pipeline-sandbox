#!/usr/bin/env bash
# Starts three background processes, each findable by a fixed argv token:
# a plain nohup, a setsid (own session), and a heartbeat writing to the checkout.
here=$(dirname "$(readlink -f "$0")")
dir=$PWD/.probe8302
mkdir -p "$dir"
nohup sleep 86401 >/dev/null 2>&1 </dev/null &
setsid nohup sleep 86402 >/dev/null 2>&1 </dev/null &
nohup bash "$here/heartbeat.sh" probe8302hb "$dir/hb" >/dev/null 2>&1 </dev/null &
sleep 3
"$here/check.sh" start-call
