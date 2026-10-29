#!/usr/bin/env python3
"""Checkpoint mode 총 cycle 로 Checkpoint-Capacity / Lookahead-Shots / iteration engines /
square engines 를 함께 고르는 sweep. 실험 38(Normal mode 연산 cycle)의 다음 단계입니다.

Checkpoint mode 총 cycle 을 세 덩어리로 나눕니다.

  실제 iteration 수 x iteration 한 번  +  measurement 수 x measurement 한 번
  + workload 마다 한 번의 초기 상태 준비  +  policy 를 기다린 시간(stall)

실제 iteration 수는 Checkpoint-Capacity / Lookahead-Shots 만으로 정해지고 software reference
model 로 RTL 없이 셉니다. iteration / measurement 한 번의 cycle 은 iteration engines /
square engines 만으로 정해지고 실험 38 의 220칸에서 식을 구했습니다. stall 은 기준점
(iteration engines 9, square engines 7)에서 Checkpoint-Capacity / Lookahead-Shots 100개를
RTL 로 잽니다. 기준점은 후보대에서 가장 빠른 쪽이라 policy 를 연산 뒤에 숨기기 가장 어렵습니다.

  iterations  K/H 100개의 실제 iteration 수 (Common500 전체와 표본)
  sim         기준점에서 K/H 100개를 표본 workloads 로 RTL simulation
  anchor      기준점의 K/H 별 iteration 수 · policy cycle · stall · 총 cycle 표와 그림 (표본 합)

표본은 target count 마다 앞의 seed --per-m 개입니다(기본 4, 곧 20 workloads). 20 workloads 에서는
Checkpoint-Capacity / Lookahead-Shots 가 어느 정도 이상이면 iteration 수가 모두 같아져 구분이 안 되므로,
--per-m 20(100 workloads)으로 다시 잴 수 있게 했습니다. 표본 크기가 다른 결과는 --out 을 달리해 따로 둡니다.
  predict     식의 상수를 맞추고, 실험 36 의 full Common500 으로 예측을 검증한 뒤
              200T 에 들어가는 모든 (K, H, iteration engines, square engines) 의 총 cycle 을 예측

예측 상위 조합을 RTL 로 다시 돌려 확인하는 단계는 두지 않습니다(사용자 결정).

policy 회로의 resource 는 판정에 넣지 않습니다(사용자 결정). 측정 축은 RTL cycle 입니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np

import engine_sweep as es
import generalize_main

ROOT = es.ROOT
# sim / anchor 단계가 잴 iteration engines / square engines. 기본은 실험 38 의 bank 분할 최소 칸이고
# main() 이 --engines 로 덮어씁니다. E/M 을 바꿔 가며 잴 때는 --out 도 E/M 마다 따로 둡니다.
ANCHOR = {"e": 9, "m": 7}
K_RANGE = range(1, 11)
H_RANGE = range(1, 11)
POLICY = {"policy_mode": 6, "scan_lanes": 4, "force_generic": True}
ENGINE_SWEEP = ROOT / "hardware_bram/results/2026-10-29_engine_sweep"
KH40 = ROOT / "hardware_bram/results/2026-10-29_generalized_common500/kh40_final"
# 표본 크기. main() 이 --per-m 으로 덮어씁니다. 표본 합의 열 이름(subset20, subset100)도 여기서 정해집니다.
PER_M = es.PER_M
SUBSET = generalize_main.per_m_indices(PER_M)


def rows(path, mode):
    return [r for r in csv.DictReader(l for l in path.open() if not l.startswith("#")) if r["mode"] == mode]


# ------------------------------------------------------------------ iterations
def iterations(base):
    out = []
    for k in K_RANGE:
        for h in H_RANGE:
            values = generalize_main.expected_iterations({"k": k, "h": h, **POLICY}, 500)
            out.append({"k": k, "h": h, "common500": sum(values),
                        f"subset{len(SUBSET)}": sum(values[i] for i in SUBSET)})
    with (base / "iterations.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(out[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(out)
    return out


# ------------------------------------------------------------------ sim
def sim_one(base_text, per_m, k, h, e, m):
    base = Path(base_text)
    data = {"k": k, "h": h, "e": e, "m": m, **POLICY}
    tag = f"k{k}h{h}e{e}m{m}"
    out = base / "cells" / tag
    if (out / "integration.json").exists():
        return tag, "cached"
    data = es.make_config(out, data)
    generalize_main.execute(data, out, per_m=per_m, console=False)
    model = json.loads((out / "model.json").read_text())
    if not model["reused"]:
        shutil.rmtree(model["directory"], ignore_errors=True)
    es.prune_snapshot(out, base / "shared")
    for name in ("build.log", "driver_build.log", "policy_trace.txt", "workload_build.log"):
        (out / name).unlink(missing_ok=True)
    return tag, "done"


def run_cells(base, cells, workers):
    failed = []
    with ProcessPoolExecutor(workers) as pool:
        jobs = {pool.submit(sim_one, str(base), PER_M, *c): c for c in cells}
        for job in as_completed(jobs):
            try:
                print(*job.result(), flush=True)
            except Exception as error:  # 실패한 조합은 기록하고 나머지를 계속 돕니다
                failed.append({"cell": list(jobs[job]), "error": str(error)})
                print(*jobs[job], "FAILED", error, flush=True)
    (base / "sim_failures.json").write_text(json.dumps(failed, indent=2) + "\n")


def sim(base, workers):
    # policy 계산이 긴 큰 Checkpoint-Capacity / Lookahead-Shots 부터 띄웁니다.
    cells = sorted(((k, h, ANCHOR["e"], ANCHOR["m"]) for k in K_RANGE for h in H_RANGE),
                   key=lambda c: -c[0] * c[1])
    run_cells(base, cells, workers)

# ------------------------------------------------------------------ predict
def shot_fit(path):
    """Checkpoint 행에서 (cycles - stall) = a x 실제 iteration + b x measurement + c 를 맞춥니다."""
    data = rows(path, "k4")
    x = np.array([[int(r["iter"]), int(r["trial"]), 1] for r in data], dtype=float)
    y = np.array([int(r["cycles"]) - int(r["policy_stall"]) for r in data], dtype=float)
    coef, *_ = np.linalg.lstsq(x, y, rcond=None)
    return coef, float(np.max(np.abs(x @ coef - y))), sum(int(r["policy_stall"]) for r in data)


def subset_stall(path):
    data = rows(path, "k4")
    if len(data) == 500:
        data = [data[i] for i in SUBSET]
    return sum(int(r["policy_stall"]) for r in data)


def predict(base):
    iters = {(int(r["k"]), int(r["h"])): int(r["common500"]) for r in csv.DictReader((base / "iterations.csv").open())}
    measurements = es.COMMON500_MEASUREMENTS

    # iteration engines / square engines 마다의 shot 비용: 실험 38 의 220칸 Checkpoint 행(K3H3).
    shot = {}
    for e in es.E_RANGE:
        for m in es.M_RANGE:
            coef, residual, _ = shot_fit(ENGINE_SWEEP / "cells" / f"e{e}m{m}" / "bench.csv")
            shot[(e, m)] = coef

    # 기준점의 K/H 100개: shot 비용이 K/H 와 무관한지 보고, 20 workloads 의 stall 을 모읍니다.
    anchor = {}
    deviation = 0.0
    for k in K_RANGE:
        for h in H_RANGE:
            coef, residual, stall = shot_fit(base / "cells" / f"k{k}h{h}e{ANCHOR['e']}m{ANCHOR['m']}" / "bench.csv")
            ref = shot[(ANCHOR["e"], ANCHOR["m"])]
            deviation = max(deviation, abs(coef[0] - ref[0]), abs(coef[1] - ref[1]))
            anchor[(k, h)] = {"stall20": stall, "residual": residual}

    # 실험 36 (iteration engines 4 / square engines 2, full Common500) 의 stall 과 같은 20 workloads 의 stall.
    kh36 = {(int(r["k"]), int(r["h"])): r for r in csv.DictReader((KH40 / "summary.csv").open())}
    kh36[(3, 3)] = {"cycles": "5148615", "iter": "9582", "policy_stall": "14013",
                    "evidence": str(ROOT / "hardware_bram/results/2026-10-29_generalized_e20_m11/baseline_common500")}
    s36 = {kh: int(r["policy_stall"]) for kh, r in kh36.items()}
    s36_20 = {kh: subset_stall(ROOT / r["evidence"] / "bench.csv") for kh, r in kh36.items()}
    base_stall, base_stall20 = s36[(1, 1)], s36_20[(1, 1)]
    # stall 은 workload 마다 첫 결정을 기다리는 고정분과, Lookahead-Shots 가 클 때 일부 workload 에
    # 몰려 생기는 추가분으로 나뉩니다. 추가분은 20 workloads 표본으로 500 을 추정하면 배수가 크게
    # 흔들리므로(실험 36 의 H6 이상에서 5~87배), 추가분이 있는 조합은 불확실로 표시하고
    # 고정분을 하한, 실험 36 배수의 중앙값으로 낸 값을 추정치로 둡니다.
    extra = [(s36[kh] - base_stall) / (s36_20[kh] - base_stall20) for kh in s36 if s36_20[kh] - base_stall20 > 0]
    scale = float(np.median(extra)) if extra else 500 / 20

    def stall500(k, h):
        a20 = anchor[(k, h)]["stall20"]
        return base_stall + max(0.0, (a20 - base_stall20) * scale)

    def stall_uncertain(k, h):
        # 표본에 추가분이 보이거나, 실험 36 에서 표본에 안 잡힌 추가분이 있던 Lookahead-Shots 6 이상.
        return anchor[(k, h)]["stall20"] != base_stall20 or h >= 6

    def total(k, h, e, m, stall):
        a, b, c = shot[(e, m)]
        return iters[(k, h)] * a + measurements * b + 500 * c + stall

    # 검증 1: 실험 36 의 실제 stall 을 넣으면 연산 부분의 식만 시험됩니다.
    # 검증 2: 실험 36 의 20 workloads stall 로 낸 추정 stall 을 넣으면 stall 추정까지 시험됩니다.
    check = []
    for (k, h), r in sorted(kh36.items()):
        actual = int(r["cycles"])
        est = base_stall + max(0.0, (s36_20[(k, h)] - base_stall20) * scale)
        check.append({"k": k, "h": h, "actual": actual,
                      "error_percent_actual_stall": round(100 * (total(k, h, 4, 2, s36[(k, h)]) - actual) / actual, 3),
                      "error_percent_estimated_stall": round(100 * (total(k, h, 4, 2, est) - actual) / actual, 3)})

    feas = {(int(r["e"]), int(r["m"])): r for r in csv.DictReader((ENGINE_SWEEP / "feasibility.csv").open())}
    preds = []
    for (e, m), r in feas.items():
        for v in es.VARIANTS:
            if r[f"{v}_feasible"] != "True":
                continue
            for k in range(1, int(r[f"{v}_max_checkpoint_capacity"]) + 1):
                for h in H_RANGE:
                    preds.append({"variant": v, "e": e, "m": m, "k": k, "h": h,
                                  "physical_iterations": iters[(k, h)], "stall_estimate": int(round(stall500(k, h))),
                                  "stall_uncertain": stall_uncertain(k, h),
                                  "checkpoint_total_predicted": int(round(total(k, h, e, m, stall500(k, h)))),
                                  "checkpoint_total_lower_bound": int(round(total(k, h, e, m, base_stall)))})
    preds.sort(key=lambda p: (p["variant"], p["checkpoint_total_predicted"]))
    with (base / "predictions.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(preds[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(preds)
    best = {}
    for p in preds:
        key = (p["variant"], p["e"], p["m"])
        if p["stall_uncertain"]:
            continue
        if key not in best or p["checkpoint_total_predicted"] < best[key]["checkpoint_total_predicted"]:
            best[key] = p
    for p in preds:
        key = (p["variant"], p["e"], p["m"])
        if key in best and p["stall_uncertain"]:
            gain = best[key]["checkpoint_total_predicted"] - p["checkpoint_total_lower_bound"]
            best[key]["uncertain_best_possible_gain"] = max(best[key].get("uncertain_best_possible_gain", 0), gain)
    with (base / "best_per_cell.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(preds[0]) + ["uncertain_best_possible_gain"],
                                lineterminator="\n", restval=0)
        writer.writeheader()
        writer.writerows(sorted(best.values(), key=lambda p: (p["variant"], p["e"], p["m"])))
    report = {
        "anchor": ANCHOR, "shot_cost_kh_independence_max_deviation": round(deviation, 3),
        "anchor_max_residual": round(max(a["residual"] for a in anchor.values()), 1),
        "stall_fixed_common500": base_stall, "stall_fixed_subset20": base_stall20,
        "stall_extra_scale_20_to_500": round(scale, 3),
        "anchor_stall20": {f"k{k}h{h}": a["stall20"] for (k, h), a in sorted(anchor.items())},
        "validation_kh36_e4m2": check,
        "validation_max_abs_error_percent": {
            "actual_stall": max(abs(c["error_percent_actual_stall"]) for c in check),
            "estimated_stall": max(abs(c["error_percent_estimated_stall"]) for c in check)},
        "top10_certain_stall": {v: [p for p in preds if p["variant"] == v and not p["stall_uncertain"]][:10]
                                for v in es.VARIANTS},
        "top5_lower_bound_any_stall": {v: sorted((p for p in preds if p["variant"] == v),
                                                 key=lambda p: p["checkpoint_total_lower_bound"])[:5]
                                       for v in es.VARIANTS},
    }
    (base / "prediction_summary.json").write_text(json.dumps(report, indent=2) + "\n")
    return report, best


# ------------------------------------------------------------------ plot
def plot(base, color_range):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import Normalize
    from matplotlib.ticker import FuncFormatter

    best = list(csv.DictReader((base / "best_per_cell.csv").open()))
    shape = (len(es.E_RANGE), len(es.M_RANGE))
    cmap = plt.get_cmap("rainbow_r").copy()
    norm = Normalize(vmin=color_range[0] / 1e6, vmax=color_range[1] / 1e6, clip=True)
    titles = {"current": "current parameterized RTL (dataset copied per iteration engine)",
              "banked": "banked dataset (memory cleanup assumed)"}
    fig, axes = plt.subplots(1, 2, figsize=(19, 13), sharey=True)
    for ax, v in zip(axes, es.VARIANTS):
        grid = np.full(shape, np.nan)
        cells = {(int(r["e"]), int(r["m"])): r for r in best if r["variant"] == v}
        for (e, m), r in cells.items():
            grid[e - 1, m - 1] = int(r["checkpoint_total_predicted"])
        image = ax.imshow(np.ma.masked_invalid(grid / 1e6), origin="lower", cmap=cmap, norm=norm, aspect="auto")
        for e in es.E_RANGE:
            for m in es.M_RANGE:
                y, x = e - 1, m - 1
                if (e, m) not in cells:
                    ax.add_patch(plt.Rectangle((x - .5, y - .5), 1, 1, facecolor="0.92", hatch="///",
                                               edgecolor="0.7", lw=0))
                    continue
                r = cells[(e, m)]
                cr, cg, cb, _ = cmap(norm(grid[y, x] / 1e6))
                ax.text(x, y, f"{grid[y, x] / 1e6:.2f}\n{r['k']}/{r['h']}", ha="center", va="center", fontsize=6,
                        color="white" if 0.299 * cr + 0.587 * cg + 0.114 * cb < 0.5 else "black")
        y, x = np.unravel_index(np.nanargmin(grid), shape)
        ax.add_patch(plt.Rectangle((x - .5, y - .5), 1, 1, fill=False, ec="black", lw=2.5))
        ax.set_xticks(range(shape[1]), list(es.M_RANGE))
        ax.set_yticks(range(shape[0]), list(es.E_RANGE))
        ax.set_xlabel("square engines")
        ax.set_title(titles[v], fontsize=10)
    axes[0].set_ylabel("iteration engines")
    fig.suptitle("CHECKPOINT MODE: predicted Common500 total RTL cycles (millions), best checkpoint capacity / "
                 "lookahead shots per cell\n"
                 "cell text: cycles / capacity/lookahead;  hatched: over 200T (LUT, FF 75%, BRAM, DSP 90%);  "
                 "box: fewest cycles;  only combinations with measured fixed policy stall (lookahead <= 5)\n"
                 f"stall measured at iteration engines {ANCHOR['e']} / square engines {ANCHOR['m']}; "
                 "policy circuit resources not included", fontsize=10)
    bar = fig.colorbar(image, ax=axes, label="RTL cycles (millions)", shrink=0.6, extend="max")
    bar.ax.yaxis.set_major_formatter(FuncFormatter(lambda val, _: f"{val:g}"))
    fig.savefig(base / "checkpoint_mode_heatmap.png", dpi=150, bbox_inches="tight")
    fig.savefig(base / "checkpoint_mode_heatmap.svg", bbox_inches="tight")


# ------------------------------------------------------------------ anchor
# anchor_kh.png 의 panel 과 색 범위입니다. 한 panel 안에서 칸 사이 차이가 색으로 보이도록 빨강은 그 panel 의
# 최솟값, 보라는 최솟값의 (1 + 비율) 배로 둡니다. 그보다 큰 칸은 모두 보라이고 값은 칸 안 숫자로 읽습니다.
# policy cycle 은 최솟값과 최댓값이 두 자릿수 넘게 벌어져 자르지 않고 log 눈금을 씁니다.
ANCHOR_PANELS = [
    ("sample_iter", "physical iterations", "linear", 0.20),
    ("sample_policy_cycles", "policy cycles", "log", None),
    ("sample_policy_stall", "policy stall cycles", "linear", 0.50),
    ("sample_cycles", "Checkpoint mode total cycles", "linear", 0.05),
]


def anchor_table(base):
    """기준점(iteration engines 9 / square engines 7)의 K/H 100개를 표본 workloads 기준으로 정리합니다.

    500 workloads 로 늘린 값이 아니라 표본 20개의 합입니다. 실제 iteration 수만 Common500 500개의
    정확값(reference model)을 함께 적습니다.
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    iters = {(int(r["k"]), int(r["h"])): r for r in csv.DictReader((base / "iterations.csv").open())}
    table = []
    for k in K_RANGE:
        for h in H_RANGE:
            path = base / "cells" / f"k{k}h{h}e{ANCHOR['e']}m{ANCHOR['m']}" / "bench.csv"
            if not path.exists():
                continue
            data = rows(path, "k4")
            # sweep 이 도는 동안에는 실행 중인 칸의 bench.csv 에 일부 workload 만 있습니다.
            # 그 합은 다른 칸과 비교할 수 없으므로 표본이 다 찬 칸만 넣습니다.
            if len(data) < len(SUBSET):
                continue
            item = {"k": k, "h": h, "workloads": len(data)}
            for field in ("iter", "policy_cycles", "policy_stall", "cycles", "policy_actions"):
                item[f"sample_{field}"] = sum(int(r[field]) for r in data)
            item["sample_max_policy_stall"] = max(int(r["policy_stall"]) for r in data)
            item["common500_iterations"] = int(iters[(k, h)]["common500"])
            item["sample_iterations_expected"] = int(iters[(k, h)][f"subset{len(SUBSET)}"])
            table.append(item)
    with (base / "anchor_table.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(table[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(table)

    from matplotlib.colors import LogNorm, Normalize
    fig, axes = plt.subplots(2, 2, figsize=(16, 14))
    for ax, (field, title, scale, spread) in zip(axes.flat, ANCHOR_PANELS):
        grid = np.full((len(K_RANGE), len(H_RANGE)), np.nan)
        for item in table:
            grid[item["k"] - 1, item["h"] - 1] = item[field]
        low = np.nanmin(grid)
        if scale == "log":
            norm = LogNorm(vmin=low, vmax=np.nanmax(grid))
            note = "log color scale"
        else:
            norm = Normalize(vmin=low, vmax=low * (1 + spread))
            note = f"purple = {norm.vmax:,.0f} or more"
        # 실험 38 heatmap 과 같이 작은 값(좋은 쪽)이 빨강, 큰 값이 보라입니다. 색 상한을 넘는 칸도
        # 보라로 칠합니다.
        cmap = plt.get_cmap("rainbow_r").copy()
        cmap.set_over(cmap(1.0))
        image = ax.imshow(np.ma.masked_invalid(grid), origin="lower", cmap=cmap, norm=norm, aspect="auto")
        for item in table:
            value = item[field]
            # 보라 · 파랑처럼 어두운 칸에서는 숫자를 흰색으로 씁니다.
            r, g, b, _ = cmap(norm(value))
            color = "white" if 0.299 * r + 0.587 * g + 0.114 * b < 0.5 else "black"
            ax.text(item["h"] - 1, item["k"] - 1, f"{value:,}", ha="center", va="center", fontsize=6.5,
                    color=color)
        ax.set_xticks(range(len(H_RANGE)), list(H_RANGE))
        ax.set_yticks(range(len(K_RANGE)), list(K_RANGE))
        ax.set_xlabel("lookahead shots")
        ax.set_ylabel("checkpoint capacity")
        ax.set_title(f"{title} ({len(SUBSET)} workloads), {note}", fontsize=10)
        fig.colorbar(image, ax=ax, shrink=0.8, extend="neither" if scale == "log" else "max")
    fig.suptitle(f"CHECKPOINT MODE at iteration engines {ANCHOR['e']} / square engines {ANCHOR['m']}: "
                 f"sums over the {len(SUBSET)}-workload sample (first {PER_M} seeds of each target count), "
                 "not Common500 totals",
                 fontsize=11)
    fig.tight_layout()
    fig.savefig(base / "anchor_kh.png", dpi=150)
    fig.savefig(base / "anchor_kh.svg")
    return table


def main():
    global PER_M, SUBSET, ANCHOR
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["iterations", "sim", "anchor", "predict", "plot"])
    parser.add_argument("--color-range", type=float, nargs=2, default=[2.0e6, 8.0e6],
                        help="plot: cycles at red and at purple")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--engines", type=int, nargs=2, metavar=("ITERATION", "SQUARE"),
                        default=[ANCHOR["e"], ANCHOR["m"]], help="sim / anchor: iteration engines and square engines")
    parser.add_argument("--per-m", type=int, default=es.PER_M,
                        help="seeds per target count in the sample (4 = 20 workloads, 20 = 100 workloads)")
    args = parser.parse_args()
    ANCHOR = {"e": args.engines[0], "m": args.engines[1]}
    PER_M = args.per_m
    SUBSET = generalize_main.per_m_indices(PER_M)
    base = args.out.resolve()
    base.mkdir(parents=True, exist_ok=True)
    if args.stage == "iterations":
        out = iterations(base)
        print(len(out), "K/H; K3H3", next(r for r in out if r["k"] == 3 and r["h"] == 3))
    elif args.stage == "sim":
        sim(base, args.workers)
    elif args.stage == "anchor":
        print(len(anchor_table(base)), "K/H rows")
    elif args.stage == "plot":
        plot(base, args.color_range)
    else:
        report, _ = predict(base)
        print(json.dumps({k: report[k] for k in report if k not in ("anchor_stall20", "validation_kh36_e4m2")}, indent=1))


if __name__ == "__main__":
    sys.exit(main())
