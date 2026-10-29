#!/usr/bin/env python3
"""Per-decision seed-first SW features for one K/H cell (full bound, seed first)."""
import sys, csv
sys.path.insert(0, sys.argv[1])
import kh_sweep, policy_search_method1 as m1
k, h, out = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
import os
wls = kh_sweep.load_workloads(kh_sweep.DEFAULT_TRACE, kh_sweep.DEFAULT_ROSTER, 10, int(os.environ["LIMIT"]) if os.environ.get("LIMIT") else None)
rows = []
for wl in wls:
    held = ()
    for i, req in enumerate(wl.requested):
        fut = tuple(wl.stream[i + 1:i + h + 1])
        pool = tuple(dict.fromkeys((req, *fut)))
        src0 = max((0, *(v for v in held if v <= req)))
        nroot = len(kh_sweep.next_states(k, held, src0, req, pool))
        src, chosen, st = m1.select_policy_action_bnb(held, req, fut, k, "seed", 0, 0)
        rows.append((1 if i == 0 else 0, nroot, req - src, st.states, st.actions, st.memo_hits,
                     st.pruned_actions + st.root_pruned_actions, st.bound_frames,
                     st.bound_candidates, st.bound_fill_cycles))
        held = chosen
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["first", "nroot", "phys", "states", "actions", "hits", "pruned", "bframes", "bcand", "bfill"])
    w.writerows(rows)
print(f"K{k}H{h} rows={len(rows)} phys={sum(r[2] for r in rows)}", flush=True)
