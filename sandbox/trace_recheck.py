"""Phase 11 probe: run babysit_merge_policy.recheck with every REST read traced.

Prints each `_get` endpoint with its HTTP status and each `_paginated` endpoint
with ok or the error, then the rung cap, kill switch and recheck results.
Report-only; the caller ignores the exit status.

Usage: trace_recheck.py SCRIPTS_DIR REPO PR BASE_SHA BASE_REF LANES_DISABLED
"""

import sys

scripts, repo, pr, base_sha, base_ref, lanes = sys.argv[1:7]
sys.path.insert(0, scripts)
import babysit_merge_policy as p  # noqa: E402

real_get, real_paginated = p._get, p._paginated


def traced_get(endpoint):
    status, payload = real_get(endpoint)
    print(f"TRACE GET {endpoint} -> {status}")
    return status, payload


def traced_paginated(endpoint, label, items_key=None):
    try:
        out = real_paginated(endpoint, label, items_key)
    except Exception as exc:
        print(f"TRACE PAGINATED {endpoint} -> error: {exc}")
        raise
    print(f"TRACE PAGINATED {endpoint} -> ok ({len(out)} items)")
    return out


p._get, p._paginated = traced_get, traced_paginated

print("== read_rung_cap:", p.read_rung_cap(repo))
print("== read_kill_switch:", p.read_kill_switch(repo))
print(
    "== recheck:",
    p.recheck(repo, int(pr), base_sha, base_ref=base_ref, lanes_disabled=lanes),
)
