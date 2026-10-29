#!/usr/bin/env python3
"""iteration engines x square engines sweep: 200T resource 판정과 shot 당 RTL cycle.

Checkpoint-Capacity / Lookahead-Shots 와 policy stall 을 빼고 연산부만 비교합니다.
네 단계를 따로 실행합니다.

  synth  지정한 구성의 bbht_rvx_wrapper OOC synthesis 사용량 (Vivado, 한 번에 하나).
         지금 일반화 RTL 은 amplitude memory 가 BRAM 으로 추론되지 않아 끝나지 않습니다
         (2026-10-29_engine_sweep/synth). memory 정리 뒤 model 의 단가 보정에 씁니다
  model  기존 200T build 의 모듈 단가와 RTL memory 구조로 1~20 x 1~11 의 200T 판정표를
         대략 계산합니다. dataset 을 지금처럼 복제할 때와 bank 로 나눌 때 두 가지입니다
  sim    1~20 x 1~11 전부를 BENCH_PER_M 층화 표본으로 RTL simulation 합니다
  plot   Normal mode 행에서 shot 당 cycle 을 구해 normal_mode_heatmap 과 summary.csv 를 씁니다.
         Normal(Restart) mode 의 순수 연산 cycle 이며 Checkpoint mode 총 cycle 과 비교하지 않습니다

Normal mode 는 policy 를 쓰지 않으므로 Checkpoint-Capacity / Lookahead-Shots 와 무관하게
같은 trajectory 를 돕니다. 그 cycle 은 iteration 수와 measurement 수의 일차식으로
거의 정확히 맞으므로(subset_check/comparison.json), 표본의 두 계수와 Common500 의 고정된
iteration / measurement 수로 Common500 Normal 합계를 예측합니다. 측정 축은 RTL cycle 이고
board · wall-clock time 과 섞지 않습니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np

import dse
import generalize
import generalize_main

ROOT = generalize.ROOT
TCL = ROOT / "hardware_bram/synth/engine_ooc.tcl"
PART = "xc7a200tfbg484-2"

# xc7a200tfbg484-2 의 사용 가능량 (route_util.rpt 의 Available 열).
DEVICE = {"lut": 133800, "ff": 267600, "bram": 365.0, "dsp": 740}
# 판정 상한. 100% 를 채우면 placement · routing 과 timing 이 사실상 안 되므로
# LUT · FF 는 75%, BRAM · DSP 는 90% 까지만 씁니다 (사용자와 정한 기준).
LIMIT = {"lut": 0.75, "ff": 0.75, "bram": 0.90, "dsp": 0.90}
# RVX SoC 에서 accelerator wrapper(i_bbht) 밖의 사용량. 2026-10-07 의 200T build 여섯 벌
# route_util_hier.rpt 에서 top - i_bbht 의 최댓값입니다 (configurations/*/vivado/*/
# 2026-10-07_ax7a200b_budget100t). 이 값은 engine 수와 무관합니다.
SOC = {"lut": 13268, "ff": 16640, "bram": 32.0, "dsp": 4}

# Normal mode 비교에 쓰는 고정 policy 설정. Normal 행은 이 값과 무관하지만 같은 실행의
# Checkpoint 행과 policy replay 검사가 돌도록 기존 기준 구성(실험 36)을 그대로 둡니다.
SIM_POLICY = {"k": 3, "h": 3, "policy_mode": 6, "scan_lanes": 4, "force_generic": True}
# resource 의 연산부 기준점. checkpoint slot 과 policy 를 가장 작게 둡니다.
SYNTH_POLICY = {"k": 1, "h": 1, "policy_mode": 6, "scan_lanes": 4, "force_generic": True}

# Common500 Normal mode 의 고정 일. engine 수와 무관합니다(subset_check 에서 확인).
# heatmap 색 축: 빨강 300만 cycle ~ 보라 1,500만 cycle (사용자 지정).
COLOR_RANGE = (3_000_000, 15_000_000)
COMMON500_ITERATIONS = 31424
COMMON500_MEASUREMENTS = 7403
PER_M = 4

E_RANGE = range(1, 21)
M_RANGE = range(1, 12)


def cell_name(data):
    return f"k{data['k']}h{data['h']}e{data['e']}m{data['m']}"


def make_config(directory, data):
    """schema 2 config 를 쓰고 generalize.config() 로 범위를 검사해 돌려줍니다."""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "config.json"
    path.write_text(json.dumps({"schema": 2, **data}, indent=2) + "\n")
    return generalize.config(path)


def prune_snapshot(out, shared):
    """칸마다 복사된 source · workload 를 공용 사본과 대조한 뒤 지웁니다.

    RTL 은 모든 칸이 같고 adapter.v 만 다릅니다. manifest.json 이 모든 source 의
    SHA-256 을 보존하므로 adapter.v 만 남깁니다. 공용 사본과 다르면 지우지 않고 멈춥니다.
    """
    for name in ("source", "workload"):
        here, there = out / name, shared / name
        if not here.exists():
            continue
        if not there.exists():
            shutil.copytree(here, there)
        for path in here.iterdir():
            if name == "source" and path.name == "adapter.v":
                continue
            if dse.digest(path) != dse.digest(there / path.name):
                raise ValueError(f"snapshot differs from shared copy: {path}")
        for path in list(here.iterdir()):
            if not (name == "source" and path.name == "adapter.v"):
                path.unlink()
        if name == "workload":
            here.rmdir()


# ------------------------------------------------------------------ synth
def parse_util(path):
    text = path.read_text()

    def row(label):
        m = re.search(rf"^\|\s*{re.escape(label)}\s*\|\s*([\d.]+)\s*\|", text, re.M)
        if not m:
            raise ValueError(f"{label} missing in {path}")
        return float(m.group(1))

    return {"lut": int(row("Slice LUTs*")), "ff": int(row("Slice Registers")),
            "bram": row("Block RAM Tile"), "dsp": int(row("DSPs"))}


def synth_one(base, data):
    out = base / "synth" / cell_name(data)
    if (out / "resource.json").exists():
        return json.loads((out / "resource.json").read_text())
    data = make_config(out, data)
    vivado = os.environ.get("VIVADO_BIN") or shutil.which("vivado")
    if not vivado:
        raise SystemExit("vivado not found; set VIVADO_BIN")
    # source snapshot 과 Vivado 의 log 는 /tmp 에서 만들고 버립니다. 결과 directory 에는
    # 구성 · source SHA-256 · adapter.v · utilization report 만 남깁니다.
    with tempfile.TemporaryDirectory(prefix="engine_ooc_") as tmp:
        cell = Path(tmp) / "cell"
        manifest = generalize_main.prepare(data, cell, 1, True, True)
        # prepare() 는 simulation 용 manifest 를 씁니다. 여기서는 synthesis 만 하므로
        # workload 항목을 빼고 범위를 바로 적습니다.
        manifest.pop("workloads")
        manifest["scope"] = "bbht_rvx_wrapper OOC synthesis utilization only (no simulation)"
        (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        shutil.copy(cell / "source" / "adapter.v", out / "adapter.v")
        env = os.environ | {"ENGINE_SRC": str(cell / "source"), "ENGINE_OUT": str(out), "ENGINE_PART": PART}
        result = subprocess.run([vivado, "-mode", "batch", "-nojournal", "-log", f"{tmp}/vivado.log",
                                 "-source", str(TCL)], cwd=tmp, env=env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        if result.returncode:
            shutil.copy(f"{tmp}/vivado.log", out / "vivado_failed.log")
            raise RuntimeError(f"synthesis failed: {out}")
    resource = parse_util(out / "util.rpt") | {"config": data}
    (out / "resource.json").write_text(json.dumps(resource, indent=2) + "\n")
    return resource


# ------------------------------------------------------------------ model
def banks(e, m):
    """grover_parallel.sv 의 amplitude bank 수: 쓰기 port e, 읽기 port max(e, max(m,4))."""
    return max(e, max(m, 4))


def amplitude_tiles(k, e, m):
    """checkpoint amplitude store 의 BRAM tile 수 (grover_ckpt_mem_parallel).

    bank 하나는 32 lanes x 23 bit = 736 bit 폭이고 깊이는 k x ceil(512/bank 수)입니다.
    깊이 512 까지는 bank 당 11 tile, 512 를 넘는 512 마다 10 tile 이 더 붙습니다.
    """
    b = banks(e, m)
    depth = k * -(-512 // b)
    chunks = -(-depth // 512)
    return b * (11 + 10 * (chunks - 1))


# 기존 RTL 의 200T routed build(2026-10-07, route_util_hier.rpt)에서 모듈별로 읽은 단가.
# 일반화 RTL 은 amplitude memory 가 BRAM 으로 추론되지 않아(synth/k1h1e20m11) 지금은
# synthesis 로 보정할 수 없으므로, 모듈 단가와 RTL 의 memory 구조로 대략 계산합니다.
#   iteration datapath  final(E4) 13,063 LUT / 9,919 FF, E1 3,036 / 1,780 의 기울기
#   oracle 정렬         E4 3,440 / 1,089 를 engine 수로 나눈 값 (E1 에는 없음)
#   dataset 한 벌       E1 의 u_data_mem 1,922 LUT, RAMB18 32 개(16 tile)
#   found mask 한 벌    E1 의 u_found_mask 65 LUT, RAMB36 1 개
#   measurement         single-row 2,174 / 6,106 / 1 tile / 64 DSP 과 dual-row 4,456 / 8,707 /
#                       2 tile / 128 DSP 의 기울기를 square engine 하나로 봅니다
#   고정분              policy · plan FIFO · planner · executor · meta(K3H3) 3,889 / 3,272 /
#                       4 tile 와 bbht · lfsr · result FIFO · status · iter_ctrl · main_ip ·
#                       mmio · loader 1,885 / 1,779, 그리고 measurement FF 의 절편 3,505
# 이 단가는 기존 RTL 의 E4 두 구성을 LUT 4~8%, FF 1% 안, BRAM tile 그대로 재현합니다(banked).
UNIT = {
    "iteration": {"lut": 3342 + 860, "ff": 2713 + 272},
    "dataset_copy": {"lut": 1922 + 65, "ff": 5, "bram": 16 + 1},
    "square": {"lut": 2282, "ff": 2601, "bram": 1, "dsp": 64},
    "fixed": {"lut": 3889 + 1885, "ff": 3272 + 1779 + 3505, "bram": 4},
}
AMP_W = 32 * 23   # amplitude memory 한 bank 의 폭(bit)

# dataset 을 어떻게 두느냐에 따른 두 가지 판정.
#   current  지금 일반화 RTL 그대로: iteration engine 마다 dataset 과 found mask 를 한 벌씩 복제
#   banked   실험 37 의 후속 memory 정리 가정: engine 수로 bank 를 나눠 한 벌만 둠. engine 하나가
#            한 cycle 에 512 bit 를 읽으므로 bandwidth 상 bank 당 RAMB36 8 개가 최소입니다.
VARIANTS = ("current", "banked")


def estimate(e, m, k, variant):
    """bbht_rvx_wrapper 의 대략 사용량 (LUT, FF, BRAM tile, DSP)."""
    b = banks(e, m)
    rp = max(e, max(m, 4))
    # amplitude 읽기 port 마다 bank 수 만큼의 mux. LUT6 하나가 4:1 이므로 bit 당 ceil(bank/4).
    crossbar = rp * AMP_W * -(-b // 4)
    oracle = UNIT["iteration"]["lut"] if e > 1 else UNIT["iteration"]["lut"] - 860
    lut = UNIT["fixed"]["lut"] + oracle + UNIT["iteration"]["lut"] * (e - 1) + crossbar + UNIT["square"]["lut"] * m
    ff = UNIT["fixed"]["ff"] + UNIT["iteration"]["ff"] * e + rp * AMP_W + UNIT["square"]["ff"] * m
    bram = UNIT["fixed"]["bram"] + amplitude_tiles(k, e, m) + UNIT["square"]["bram"] * m
    if variant == "current":
        lut += UNIT["dataset_copy"]["lut"] * e
        bram += UNIT["dataset_copy"]["bram"] * e
    else:
        lut += UNIT["dataset_copy"]["lut"] + 552 * (e - 1)   # final(E4) u_data_mem 3,579 LUT 의 기울기
        bram += max(16, 8 * e) + max(1, -(-e // 2))
    return {"lut": lut, "ff": ff, "bram": float(bram), "dsp": UNIT["square"]["dsp"] * m}


def model(base):
    bram_cap = DEVICE["bram"] * LIMIT["bram"]
    rows = []
    for e in E_RANGE:
        for m in M_RANGE:
            row = {"e": e, "m": m, "banks": banks(e, m), "amplitude_tiles_k1": amplitude_tiles(1, e, m)}
            for v in VARIANTS:
                total = {key: value + SOC[key] for key, value in estimate(e, m, 1, v).items()}
                over = [key for key in DEVICE if total[key] > DEVICE[key] * LIMIT[key]]
                # 연산부가 들어가는 칸에서 BRAM 90% 안에 둘 수 있는 가장 큰 Checkpoint-Capacity.
                # policy 의 LUT · BRAM 증가는 넣지 않습니다(연산부 비교 단계의 범위 밖).
                max_k = max([k for k in range(1, 11)
                             if estimate(e, m, k, v)["bram"] + SOC["bram"] <= bram_cap], default=0)
                row |= {**{f"{v}_{key}_percent": round(100 * total[key] / DEVICE[key], 1) for key in DEVICE},
                        f"{v}_feasible": not over, f"{v}_over": "+".join(over),
                        f"{v}_max_checkpoint_capacity": max_k if not over else 0}
            rows.append(row)
    with (base / "feasibility.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    (base / "resource_model.json").write_text(json.dumps({
        "device": PART, "available": DEVICE, "limit_fraction": LIMIT, "soc_outside_wrapper": SOC,
        "unit_costs": UNIT, "amplitude_word_bits": AMP_W, "variants": list(VARIANTS),
        "scope": "rough estimate from 2026-10-07 routed module costs and RTL memory structure; "
                 "not a synthesis result",
        **{f"{v}_feasible_cells": sum(r[f"{v}_feasible"] for r in rows) for v in VARIANTS},
        "cells": len(rows)}, indent=2) + "\n")
    return rows


# ------------------------------------------------------------------ sim
def sim_one(base_text, e, m):
    base = Path(base_text)
    data = SIM_POLICY | {"e": e, "m": m}
    out = base / "cells" / f"e{e}m{m}"
    if (out / "integration.json").exists():
        return e, m, "cached"
    data = make_config(out, data)
    generalize_main.execute(data, out, per_m=PER_M, console=False)
    model_info = json.loads((out / "model.json").read_text())
    # 이번 실행이 새로 만든 compiled model 만 지웁니다 (칸당 150~230 MB, 재사용하지 않음).
    if not model_info["reused"]:
        shutil.rmtree(model_info["directory"], ignore_errors=True)
    prune_snapshot(out, base / "shared")
    # Verilator 경고 log 와 Checkpoint 행의 policy trace 는 다시 돌리면 그대로 나옵니다.
    # replay 검사 결과는 integration.json 에 남으므로 칸마다 지웁니다 (220칸 합계 약 31 MB).
    for name in ("build.log", "driver_build.log", "policy_trace.txt", "workload_build.log"):
        (out / name).unlink(missing_ok=True)
    return e, m, "done"


def sim(base, workers):
    # 칸당 1분 안팎이라 1~20 x 1~11 전부를 돌립니다. 200T 판정은 plot 에서 겹쳐 그리므로
    # resource 가정을 바꿔도 simulation 을 다시 돌릴 필요가 없습니다.
    cells = [(e, m) for e in E_RANGE for m in M_RANGE]
    # 큰 구성일수록 compile 이 길어 먼저 띄웁니다.
    cells.sort(key=lambda c: -(c[0] + c[1]))
    failed = []
    with ProcessPoolExecutor(workers) as pool:
        jobs = {pool.submit(sim_one, str(base), e, m): (e, m) for e, m in cells}
        for job in as_completed(jobs):
            e, m = jobs[job]
            try:
                print(*job.result(), flush=True)
            except Exception as error:  # 실패한 칸은 기록하고 나머지를 계속 돕니다
                failed.append({"e": e, "m": m, "error": str(error)})
                print(e, m, "FAILED", error, flush=True)
    (base / "sim_failures.json").write_text(json.dumps(failed, indent=2) + "\n")


# ------------------------------------------------------------------ plot
def shot_costs(path):
    rows = [r for r in csv.DictReader(l for l in path.open() if not l.startswith("#")) if r["mode"] == "normal"]
    a = np.array([[int(r["iter"]), int(r["trial"]), 1] for r in rows], dtype=float)
    y = np.array([int(r["cycles"]) for r in rows], dtype=float)
    coef, *_ = np.linalg.lstsq(a, y, rcond=None)
    residual = float(np.max(np.abs(a @ coef - y)))
    return coef, residual, int(y.sum())


def outline(ax, mask, **style):
    """True 칸들의 바깥 경계를 칸 모서리를 따라 그립니다."""
    rows, cols = mask.shape
    for y in range(rows):
        for x in range(cols):
            if not mask[y, x]:
                continue
            for dy, dx, xs, ys in ((1, 0, (x - .5, x + .5), (y + .5, y + .5)), (-1, 0, (x - .5, x + .5), (y - .5, y - .5)),
                                   (0, 1, (x + .5, x + .5), (y - .5, y + .5)), (0, -1, (x - .5, x - .5), (y - .5, y + .5))):
                ny, nx = y + dy, x + dx
                if not (0 <= ny < rows and 0 <= nx < cols) or not mask[ny, nx]:
                    ax.plot(xs, ys, **style)


def plot(base):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    feas = {(int(r["e"]), int(r["m"])): r for r in csv.DictReader((base / "feasibility.csv").open())}
    shape = (len(E_RANGE), len(M_RANGE))
    grid = np.full(shape, np.nan)
    ok = {v: np.zeros(shape, bool) for v in VARIANTS}
    summary = []
    for (e, m), r in sorted(feas.items()):
        item = {"e": e, "m": m, "banks": r["banks"]}
        for v in VARIANTS:
            ok[v][e - 1, m - 1] = r[f"{v}_feasible"] == "True"
            item |= {f"{v}_feasible": r[f"{v}_feasible"], f"{v}_over": r[f"{v}_over"],
                     f"{v}_lut_percent": r[f"{v}_lut_percent"], f"{v}_bram_percent": r[f"{v}_bram_percent"],
                     f"{v}_max_checkpoint_capacity": r[f"{v}_max_checkpoint_capacity"]}
        bench = base / "cells" / f"e{e}m{m}" / "bench.csv"
        if (bench.parent / "integration.json").exists():
            coef, residual, sample = shot_costs(bench)
            predicted = coef[0] * COMMON500_ITERATIONS + coef[1] * COMMON500_MEASUREMENTS + coef[2] * 500
            item |= {"per_iteration": round(coef[0], 2), "per_measurement": round(coef[1], 2),
                     "max_residual": round(residual, 1), "sample_normal_cycles": sample,
                     "common500_normal_predicted": int(round(predicted))}
            grid[e - 1, m - 1] = predicted
        summary.append(item)
    with (base / "summary.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(summary[0]) + [
            "per_iteration", "per_measurement", "max_residual", "sample_normal_cycles",
            "common500_normal_predicted"], restval="", lineterminator="\n")
        writer.writeheader()
        writer.writerows(summary)

    fig, ax = plt.subplots(figsize=(11, 14))
    # 빨강(빠름) = 300만 cycle, 보라(느림) = 1,500만 cycle. 그보다 느린 칸(iteration engines 1~2)은
    # 보라로 포화시키고 색 막대 끝에 표시합니다. 경계 안쪽의 차이가 보이도록 선형 축을 씁니다.
    from matplotlib.colors import Normalize
    cmap = plt.get_cmap("rainbow_r").copy()
    norm = Normalize(vmin=COLOR_RANGE[0] / 1e6, vmax=COLOR_RANGE[1] / 1e6, clip=True)
    image = ax.imshow(np.ma.masked_invalid(grid / 1e6), origin="lower", cmap=cmap, norm=norm, aspect="auto")

    def text_color(value):
        r, g, b, _ = cmap(norm(value / 1e6))
        return "white" if 0.299 * r + 0.587 * g + 0.114 * b < 0.5 else "black"

    for (e, m), r in feas.items():
        y, x = e - 1, m - 1
        if not ok["banked"][y, x]:
            ax.add_patch(plt.Rectangle((x - .5, y - .5), 1, 1, facecolor="white", alpha=0.55,
                                       hatch="///", edgecolor="0.55", lw=0))
        # 첫 줄: Common500 Normal cycle(백만). 아직 simulation 전이면 "-".
        # 둘째 줄: 들어가는 칸은 BRAM 90% 안의 최대 Checkpoint-Capacity, 넘치는 칸은 넘친 자원.
        label = f"{grid[y, x] / 1e6:.2f}" if np.isfinite(grid[y, x]) else "-"
        if ok["banked"][y, x]:
            label += f"\n<={r['banked_max_checkpoint_capacity']}"
            if ok["current"][y, x] and r["current_max_checkpoint_capacity"] != r["banked_max_checkpoint_capacity"]:
                label += f" ({r['current_max_checkpoint_capacity']})"
        else:
            label += "\n" + r["banked_over"]
        color = text_color(grid[y, x]) if np.isfinite(grid[y, x]) and ok["banked"][y, x] else "black"
        ax.text(x, y, label, ha="center", va="center", fontsize=6, color=color)
    outline(ax, ok["current"], color="black", lw=2.2)
    outline(ax, ok["banked"], color="black", lw=1.4, ls="--")
    for v, color in (("current", "orange"), ("banked", "red")):
        masked = np.where(ok[v], grid, np.nan)
        if np.isfinite(masked).any():
            y, x = np.unravel_index(np.nanargmin(masked), shape)
            ax.add_patch(plt.Rectangle((x - .5, y - .5), 1, 1, fill=False, ec=color, lw=2.5))
    ax.set_xticks(range(shape[1]), list(M_RANGE))
    ax.set_yticks(range(shape[0]), list(E_RANGE))
    ax.set_xlabel("square engines")
    ax.set_ylabel("iteration engines")
    ax.set_title("NORMAL (RESTART) MODE ONLY: compute-cycle reduction by iteration / square engines\n"
                 "Not comparable with Checkpoint mode totals (no checkpoint reuse, no policy; "
                 "all 31,424 requested iterations run)\n"
                 "Common500 RTL cycles (millions), predicted from 20-workload shot costs\n"
                 "solid: fits 200T with the current parameterized RTL; dashed: fits with banked dataset;\n"
                 "hatched: over 200T even with banked dataset (second line: resource over limit);\n"
                 "<=n (m): largest checkpoint capacity within 90% BRAM, banked (current RTL if different);\n"
                 "orange / red box: fewest cycles inside solid / dashed region", fontsize=9)
    from matplotlib.ticker import FuncFormatter
    bar = fig.colorbar(image, ax=ax, label="RTL cycles (millions)", shrink=0.6, extend="max")
    bar.ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:g}"))
    bar.ax.yaxis.set_minor_formatter(FuncFormatter(lambda v, _: f"{v:g}"))
    fig.tight_layout()
    fig.savefig(base / "normal_mode_heatmap.png", dpi=150)
    fig.savefig(base / "normal_mode_heatmap.svg")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["synth", "model", "sim", "plot"])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--point", action="append", default=[],
                        help="synth: e,m (Checkpoint-Capacity / Lookahead-Shots 1/1) or k,h,e,m")
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()
    base = args.out.resolve()
    if args.stage == "synth":
        for text in args.point:
            values = [int(v) for v in text.split(",")]
            data = SYNTH_POLICY | dict(zip("em" if len(values) == 2 else "khem", values))
            print(cell_name(data), synth_one(base, data), flush=True)
    elif args.stage == "model":
        rows = model(base)
        for v in VARIANTS:
            print(v, "feasible", sum(r[f"{v}_feasible"] for r in rows), "/", len(rows))
    elif args.stage == "sim":
        sim(base, args.workers)
    else:
        plot(base)


if __name__ == "__main__":
    sys.exit(main())
