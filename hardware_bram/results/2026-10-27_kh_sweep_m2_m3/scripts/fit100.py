#!/usr/bin/env python3
"""K1..10 x H1..10 extrapolation for M3 + EXACT_PRUNE=6 (unlimited-resource what-if).

Uses the M3 coefficients fitted in h40/fit_report_m3.json:
  per-decision latency  L = x . c          (mode 6, K3/K4 x H1..8 standalone RTL)
  stall                 c0*n + c1*sum(L_first) + c2*sum(max(0, L_rest - tau))
  total                 F + b*physical + stall
Common assumptions for every cell (so the 100 cells compare like for like):
  * no memo clear cost (a wide epoch tag means no wrap during the run); the
    K3/K4 H<=8 RTL latencies have their measured clear cycles removed
  * Shadow-J supplies H futures; amplitude storage / BRAM is unlimited
"""
import csv, json, sys
from math import comb
from pathlib import Path
import numpy as np

S = Path("/tmp/claude-1000/-workspace/e2bf3af7-5088-4566-a65a-8c884cbf49eb/scratchpad")
sys.path.insert(0, str(S / "wt/hardware_bram/sim"))
import kh_sweep  # noqa: E402

REP = json.load(open(S / "h40/fit_report_m3.json"))
COEF = np.array(REP["latency_coef"]["6"])
ST = REP["stall_params"]; TP = REP["total_params"]
WLS = kh_sweep.load_workloads(kh_sweep.DEFAULT_TRACE, kh_sweep.DEFAULT_ROSTER, 10, None)
NDEC = [len(w.requested) for w in WLS]
NORMAL = float(sum(sum(w.requested) for w in WLS))
FIRST = np.zeros(sum(NDEC), bool)
i = 0
for n in NDEC:
    FIRST[i] = True; i += n


def clear_vec(k, h, n):
    v = np.zeros(n)
    v[0::255] = 3 * 127 if (k, h) == (3, 3) else h * 1093
    return v


def load_sw(k, h):
    rows = list(csv.DictReader(open(S / f"h100/sw_k{k}h{h}.csv")))
    a = {c: np.array([float(r[c]) for r in rows]) for c in rows[0]}
    a["h"] = np.full(len(rows), float(h))
    return a


def features(sw):
    forced = (sw["nroot"] == 1).astype(float)
    live = 1.0 - forced
    return np.vstack([live, sw["states"] * live, sw["actions"] * live, sw["bframes"] * live,
                      sw["bcand"] * live, sw["bfill"] * live, sw["hits"] * live,
                      sw["pruned"] * live, sw["h"] * live, forced, forced * sw["h"]]).T


def rtl_latency(k, h):
    f = S / f"h40/rtl_k{k}h{h}_p6.txt"
    L = np.array([float(l.split(",")[2]) for l in open(f) if l.startswith("ROW")])
    return L - clear_vec(k, h, len(L))


out = []
for k in range(1, 11):
    for h in range(1, 11):
        sw = load_sw(k, h)
        if k in (3, 4) and h <= 8:
            L, src = rtl_latency(k, h), "RTL latency"
        else:
            L, src = np.maximum(features(sw) @ COEF, 1.0), "model latency"
        stall = (ST["c_per_decision"] * len(L) + ST["c_first"] * L[FIRST].sum()
                 + ST["c_excess"] * np.maximum(0.0, L[~FIRST] - ST["tau"]).sum())
        phys = sw["phys"].sum()
        total = TP["F"] + TP["b"] * phys + stall
        out.append(dict(k=k, h=h, physical=int(phys), reduction_pct=100 * (1 - phys / NORMAL),
                        policy_per_decision=L.mean(), stall=int(stall), total=int(total),
                        latency_source=src))
w = csv.DictWriter(open(S / "h100/kh100_m3_p6.csv", "w", newline=""), fieldnames=list(out[0]))
w.writeheader(); w.writerows(out)
best = sorted(out, key=lambda r: r["total"])
print("top 12:")
for r in best[:12]:
    print(f"  K{r['k']}H{r['h']}: total {r['total']:,} phys {r['physical']:,} "
          f"pol/dec {r['policy_per_decision']:.0f} stall {r['stall']:,} [{r['latency_source']}]")
ref = next(r for r in out if r["k"] == 3 and r["h"] == 3)
print(f"K3H3 under the same assumptions: {ref['total']:,}")
print("best H per K:", {k: min((r for r in out if r["k"] == k), key=lambda r: r["total"])["h"] for k in range(1, 11)})
print("min physical over grid:", min(r["physical"] for r in out))
