#!/usr/bin/env python3
"""40-cell K/H estimate for M3 + seed-first policy (EXACT_PRUNE 5/6).

Evidence levels per cell
  measured   : K3/K4 H1..6  integrated bench500 (total, stall) + standalone policy RTL
  rtl+model  : K3/K4 H7..8  standalone policy RTL measured; stall/total from the
               fitted system model (integrated Shadow-J only supplies 7 futures)
  model      : K1/K2/K5     per-decision policy latency predicted from SW
               seed-first features; stall/total from the fitted system model

Models
  latency    : L_i = clear_i + x_i . c        (per mode, least squares, 16 cells)
  stall      : stall_i = max(0, L_i - T_i),   T_first = d0, T_i = a*phys_{i-1} + d
               plus e per decision (integrated bookkeeping overhead)
  total      : total = F + b*phys + stall     (fitted on the 12 measured cells x 2 modes)
"""
import csv, json, sys
from math import comb
from pathlib import Path
import numpy as np
from scipy.optimize import least_squares

S = Path("/tmp/claude-1000/-workspace/e2bf3af7-5088-4566-a65a-8c884cbf49eb/scratchpad")
sys.path.insert(0, str(S / "wt/hardware_bram/sim"))
import kh_sweep  # noqa: E402

WLS = kh_sweep.load_workloads(kh_sweep.DEFAULT_TRACE, kh_sweep.DEFAULT_ROSTER, 8, None)
KEYS = [(w.target_count, w.seed_index) for w in WLS]
NDEC = [len(w.requested) for w in WLS]
CELLS = [(k, h) for k in range(1, 6) for h in range(1, 9)]
MEASURED = {(k, h) for k in (3, 4) for h in range(1, 7)}
RTL_CELLS = {(k, h) for k in (3, 4) for h in range(1, 9)}
import os
# Variant selection: TAG names the measurement-path build (m3 / m2), KH_DIR holds
# its integrated bench500 CSVs, MODES the policy modes measured there.
TAG = os.environ.get("TAG", "m3")
KH_DIR = os.environ.get("KH_DIR", "kh")
MODES = tuple(int(m) for m in os.environ.get("MODES", "5,6").split(","))
# Baseline: M3 prune0 K3H3 integrated (evidence 1e32e08, reproduced); override per variant.
BASE_M3 = int(os.environ.get("BASE", "4680014"))


def mem_entries(k, h):
    """Memo words cleared at reset / epoch wrap (grover_policy.v MEM_ENTRIES).
    K3H3 uses the compact 127-rank layout; K3/K4 otherwise the 1,093 stride.
    K1/K2/K5 have no RTL; use the exact reachable-rank count sum C(U,<=K)."""
    if (k, h) == (3, 3):
        return 3 * 127
    if k in (3, 4):
        return h * 1093
    u = k + h + 1
    return h * sum(comb(u, c) for c in range(k + 1))


def clear_vec(k, h, n):
    v = np.zeros(n)
    v[0::255] = mem_entries(k, h)  # reset, then every epoch wrap (255 solves)
    return v


def load_sw(k, h):
    rows = list(csv.DictReader(open(S / f"h40/sw_k{k}h{h}.csv")))
    a = {c: np.array([float(r[c]) for r in rows]) for c in rows[0]}
    a["h"] = np.full(len(rows), float(h))
    return a


def load_rtl(k, h, p):
    return np.array([float(l.split(",")[2]) for l in open(S / f"h40/rtl_k{k}h{h}_p{p}.txt")
                     if l.startswith("ROW")])


def features(sw, mode):
    one = np.ones_like(sw["states"])
    forced = (sw["nroot"] == 1).astype(float) if mode == 6 else np.zeros_like(one)
    live = 1.0 - forced
    x = [live, sw["states"] * live, sw["actions"] * live, sw["bframes"] * live,
         sw["bcand"] * live, sw["bfill"] * live, sw["hits"] * live, sw["pruned"] * live,
         sw["h"] * live]
    if mode == 6:
        x += [forced, forced * sw["h"]]
    return np.vstack(x).T


def fit_latency(mode):
    xs, ys, idx = [], [], []
    for (k, h) in sorted(RTL_CELLS):
        sw = load_sw(k, h)
        y = load_rtl(k, h, mode) - clear_vec(k, h, len(sw["states"]))
        xs.append(features(sw, mode)); ys.append(y); idx.append((k, h))
    coef = np.linalg.lstsq(np.vstack(xs), np.concatenate(ys), rcond=None)[0]
    # leave-one-cell-out error on cell totals
    loco = {}
    for j, cell in enumerate(idx):
        X = np.vstack([x for i, x in enumerate(xs) if i != j])
        Y = np.concatenate([y for i, y in enumerate(ys) if i != j])
        c = np.linalg.lstsq(X, Y, rcond=None)[0]
        pred = (xs[j] @ c).sum(); true = ys[j].sum()
        loco[cell] = (pred - true) / (true + clear_vec(*cell, len(ys[j])).sum())
    return coef, loco


def latency(k, h, mode, coef):
    sw = load_sw(k, h)
    if (k, h) in RTL_CELLS:
        return load_rtl(k, h, mode), sw
    pred = features(sw, mode) @ coef
    return np.maximum(pred, 1.0) + clear_vec(k, h, len(pred)), sw


def split(v):
    out, i = [], 0
    for n in NDEC:
        out.append(v[i:i + n]); i += n
    return out


def stall_of(L, phys, a, d, d0, e):
    tot = 0.0
    for Lw, Pw in zip(split(L), split(phys)):
        T = np.empty_like(Lw); T[0] = d0; T[1:] = a * Pw[:-1] + d
        tot += np.maximum(0.0, Lw - T).sum() + e * len(Lw)
    return tot


def integ(k, h, p):
    rows = [r for r in csv.DictReader(l for l in open(S / f"{KH_DIR}/k{k}h{h}_p{p}.csv")
                                     if not l.startswith("#")) if r["mode"] != "normal"]
    return sum(int(r["cycles"]) for r in rows), sum(int(r["policy_stall"]) for r in rows)


def main():
    lat = {m: fit_latency(m) for m in MODES}
    meas = {(k, h, p): integ(k, h, p) for (k, h) in MEASURED for p in MODES}
    # cell-level stall model: stall = c0*n + c1*sum(L_first) + c2*sum(max(0, L_rest - tau))
    # (first decision of a workload is a cold solve with nothing to hide behind;
    #  later decisions only expose latency beyond ~one shot of Grover work).
    def sfeat(L, tau):
        f = np.zeros(len(L), bool); i = 0
        for n in NDEC:
            f[i] = True; i += n
        return np.array([len(L), L[f].sum(), np.maximum(0.0, L[~f] - tau).sum()])
    pts = []
    for (k, h) in sorted(MEASURED):
        phys = load_sw(k, h)["phys"].sum()
        for p in MODES:
            tot, st = meas[(k, h, p)]
            pts.append(((k, h, p), load_rtl(k, h, p), phys, tot, st))

    def fit_all(sel, tau):
        X = np.array([sfeat(pt[1], tau) for pt in sel]); ys = np.array([pt[4] for pt in sel])
        c = np.linalg.lstsq(X, ys, rcond=None)[0]
        A = np.vstack([np.ones(len(sel)), [pt[2] for pt in sel]]).T
        fb = np.linalg.lstsq(A, np.array([pt[3] - pt[4] for pt in sel]), rcond=None)[0]
        return c, fb

    def loco(tau):
        errs = {}
        for j, pt in enumerate(pts):
            c, (F_, b_) = fit_all(pts[:j] + pts[j + 1:], tau)
            pred = F_ + b_ * pt[2] + sfeat(pt[1], tau) @ c
            errs[pt[0]] = 100 * (pred - pt[3]) / pt[3]
        return errs
    scan = {t: loco(t) for t in range(200, 420, 10)}
    tau = min(scan, key=lambda t: max(abs(v) for v in scan[t].values()))
    st_c, (F, b) = fit_all(pts, tau)
    loco_total = scan[tau]

    out = []
    for (k, h) in CELLS:
        for p in MODES:
            L, sw = latency(k, h, p, lat[p][0])
            phys = sw["phys"].sum()
            st_model = float(sfeat(L, tau) @ st_c)
            tot_model = F + b * phys + st_model
            if (k, h) in MEASURED:
                tot, st, level = *meas[(k, h, p)], "measured"
            else:
                tot, st = tot_model, st_model
                level = "rtl+model" if (k, h) in RTL_CELLS else "model"
            out.append(dict(k=k, h=h, mode=p, level=level, physical=int(phys),
                            phys_reduction_pct=100 * (1 - phys / sw_normal),
                            policy_cycles=int(L.sum()), policy_per_decision=L.sum() / len(L),
                            stall=int(round(st)), total=int(round(tot)),
                            stall_pct=100 * st / tot, model_total=int(round(tot_model)),
                            model_stall=int(round(st_model)),
                            vs_m3_prune0_pct=100 * (tot - BASE_M3) / BASE_M3,
                            hw="no: K5 needs 5th amplitude slot (BRAM)" if k == 5 else
                               ("no: RTL checkpoint is K3/K4" if k < 3 else
                                ("partial: Shadow-J gives 7 futures" if h > 6 else "yes"))))
    w = csv.DictWriter(open(S / f"h40/kh40_{TAG}.csv", "w", newline=""), fieldnames=list(out[0]))
    w.writeheader(); w.writerows(out)
    rep = dict(latency_coef={m: lat[m][0].tolist() for m in MODES},
               latency_loco_pct={m: {f"K{k}H{h}": round(100 * v, 2) for (k, h), v in lat[m][1].items()} for m in MODES},
               stall_params=dict(tau=tau, c_per_decision=st_c[0], c_first=st_c[1], c_excess=st_c[2]),
               total_params=dict(F=F, b=b),
               loco_total_pct={f"K{k}H{h}p{p}": round(v, 3) for (k, h, p), v in loco_total.items()},
               model_check={f"K{r['k']}H{r['h']}p{r['mode']}": dict(total_err_pct=round(100 * (r['model_total'] - r['total']) / r['total'], 3),
                                                                    stall_meas=r['stall'], stall_model=r['model_stall'])
                            for r in out if r['level'] == 'measured'})
    json.dump(rep, open(S / f"h40/fit_report_{TAG}.json", "w"), indent=1)
    print(json.dumps({k: rep[k] for k in ("stall_params", "total_params")}, indent=1))
    print("LOCO latency %:", rep["latency_loco_pct"])
    print("model check:", rep["model_check"])


sw_normal = None
if __name__ == "__main__":
    sw_normal = float(sum(sum(w.requested) for w in WLS))
    main()
