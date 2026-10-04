---
name: audit-env
description: Report which credential variables a Bash subprocess and its ancestors can see. Test fixture for the pr-run-activity runner.
allowed-tools: Bash
---

Run the command below with the Bash tool exactly as written, as one call, and change nothing in
it. It prints variable names, counts and lengths only, never a value. Then reply with its complete
output, verbatim, inside one fenced block, and nothing else. If the Bash call is refused or fails,
reply with the exact error text instead.

```bash
summ() { src=$1; f=$2; raw=$(cat -- "$f" 2>/dev/null | tr '\0' '\n'); if [ -z "$raw" ]; then echo "$src: unreadable or empty: $(cat -- "$f" 2>&1 >/dev/null)"; return; fi; echo "$src: vars=$(grep -c = <<<"$raw") CLAUDE_CODE_OAUTH_TOKEN=$(grep -c '^CLAUDE_CODE_OAUTH_TOKEN=' <<<"$raw") CLAUDE_CODE_OAUTH*=$(grep -c '^CLAUDE_CODE_OAUTH' <<<"$raw") ANTHROPIC*=$(grep -c '^ANTHROPIC' <<<"$raw") sk-ant-values=$(grep -c 'sk-ant-' <<<"$raw") GH_TOKEN=$(grep -c '^GH_TOKEN=' <<<"$raw") GITHUB_TOKEN=$(grep -c '^GITHUB_TOKEN=' <<<"$raw") ACTIONS_RUNTIME_TOKEN=$(grep -c '^ACTIONS_RUNTIME_TOKEN=' <<<"$raw")"; echo "$src credential-like names: $(cut -d= -f1 <<<"$raw" | grep -E 'TOKEN|OAUTH|SECRET|KEY|PASS|AUTH|CRED|GIT_CONFIG|ANTHROPIC_API' | sort | tr '\n' ' ')"; }
p=$PPID; gp=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
echo "pid=$$ comm=$(cat /proc/$$/comm 2>&1) ppid=$p comm=$(cat /proc/$p/comm 2>&1) gppid=${gp:-none} comm=$(cat /proc/${gp:-0}/comm 2>&1)"
echo "visible pids: $(ls -d /proc/[0-9]* 2>/dev/null | wc -l)"
summ env <(env -0)
summ self "/proc/$$/environ"
summ ppid "/proc/$p/environ"
summ gppid "/proc/${gp:-0}/environ"
echo "gh api: $(gh api repos/melodic-software/pr-pipeline-sandbox --jq .full_name 2>&1 | head -n 2 | tr '\n' ' ')"
echo "curl api.github.com: $(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 https://api.github.com 2>&1 | head -n 2 | tr '\n' ' ')"
```
