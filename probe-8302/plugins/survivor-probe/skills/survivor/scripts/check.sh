#!/usr/bin/env bash
# usage: check.sh <label> [wait seconds] [--self-control]
# Prints process ids, namespace ids and counts only. It reads /proc/<pid>/cmdline
# and stat, and never environ.
label=$1
wait=${2:-0}
self=${3:-}
[ "$wait" = 0 ] || sleep "$wait"
dir=$PWD/.probe8302
if [ "$self" = --self-control ]; then
  sleep 86403 >/dev/null 2>&1 </dev/null &
  sleep 1
fi
declare -A count=([86401]=0 [86402]=0 [86403]=0 [86404]=0 [hb]=0)
details=()
visible=0
for proc in /proc/[0-9]*; do
  pid=${proc#/proc/}
  [ "$pid" != "$$" ] || continue
  visible=$((visible + 1))
  cmd=$(tr '\0' ' ' <"$proc/cmdline" 2>/dev/null) || continue
  case "$cmd" in
    "sleep 86401 "*) token=86401 ;;
    "sleep 86402 "*) token=86402 ;;
    "sleep 86403 "*) token=86403 ;;
    "sleep 86404 "*) token=86404 ;;
    *probe8302hb*) token=hb ;;
    *) continue ;;
  esac
  count[$token]=$((count[$token] + 1))
  read -r _ _ _ ppid pgid sid _ <<<"$(sed 's/^[0-9]* ([^)]*)/x x/' "$proc/stat" 2>/dev/null)"
  details+=("token=$token pid=$pid ppid=$ppid pgid=$pgid sid=$sid pidns=$(readlink "$proc/ns/pid" 2>/dev/null)")
done
now=$(date +%s)
hb_lines=0
hb_age=none
if [ -f "$dir/hb" ]; then
  hb_lines=$(wc -l <"$dir/hb")
  hb_age=$((now - $(tail -n 1 "$dir/hb")))
fi
{
  echo "probe8302 $label utc=$now pid=$$ pidns=$(readlink /proc/self/ns/pid) visible_pids=$visible sleep86401=${count[86401]} sleep86402=${count[86402]} sleep86403=${count[86403]} sleep86404=${count[86404]} heartbeat=${count[hb]} hb_lines=$hb_lines hb_age_s=$hb_age"
  for detail in "${details[@]}"; do
    echo "probe8302 $label match $detail"
  done
} | tee -a "$dir/log"
