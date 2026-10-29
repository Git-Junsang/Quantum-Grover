#!/usr/bin/env python3
"""범용 RTL 의 OOC synthesis 실측으로 200T resource 경계를 다시 정합니다.

실험 38 의 판정(engine_sweep.model)은 범용 RTL 이 synthesis 되지 않아 기존 E4 전용 build 의 모듈
단가를 빌려 썼습니다. amplitude memory 와 policy 후보 cache 를 BRAM 형태로 고친 뒤에는 범용 RTL 을
직접 synthesis 할 수 있으므로, 여러 점의 계층별 사용량으로 블록마다 단가를 다시 구합니다.

  collect  engine_sweep.py synth 결과 directory 에서 점마다 계층별 사용량을 읽어 points.csv 와
           원 report 사본을 만듭니다.
  fit      Checkpoint-Capacity / Lookahead-Shots 3/3 점으로 연산부 블록 단가를 맞추고, iteration
           engines / square engines 4/4 점으로 policy 의 Checkpoint-Capacity / Lookahead-Shots 별
           사용량 표를 만든 뒤 칸마다 200T 판정(calibrated_feasibility.csv)을 냅니다.

판정 기준은 실험 38 과 같습니다(LUT · FF 75%, BRAM · DSP 90%, wrapper 밖 SoC 사용량 포함, timing 제외).
policy 사용량은 실측한 Checkpoint-Capacity / Lookahead-Shots 조합에서만 쓰고 그 밖으로 외삽하지 않습니다.

현재 상태(작업 중): fit 의 연산부 식은 iteration engines 에 대한 직선이라 아직 쓰면 안 됩니다. synthesis 에서
amplitude 읽기 · 쓰기 mux 와 datapath 가 bank 수 = iteration engines 이고 2 의 거듭제곱일 때만 작아지고
(E8M4 대 E10M4 · E8M9), 그 밖에는 port x bank mux 가 남는 것이 확인되어 bank 구조별로 다시 맞출 예정입니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import shutil
import sys
from math import comb, ceil, log2
from pathlib import Path

import numpy as np

import engine_sweep as es

# util.rpt 의 Available 열(xc7a200tfbg484-2). engine_sweep.DEVICE 는 기존 routed build 의 값이라
# LUT · FF 가 조금 작습니다. synthesis 실측과 같은 report 의 분모를 씁니다.
DEVICE = {"lut": 134600, "ff": 269200, "bram": 365.0, "dsp": 740}
LIMIT = es.LIMIT
SOC = es.SOC
SUPPORTED_E = range(1, 11)   # grover_param.vh GP_MAX_INTRA_ENGINES
SUPPORTED_M = range(1, 10)   # grover_param.vh GP_MAX_SQUARE_ENGINES
BLOCKS = ("policy", "dataset", "amplitude", "datapath", "control", "measurement", "rest")
FIELDS = ("lut", "ff", "bram", "dsp")


# ------------------------------------------------------------------ collect
def parse_hier(path):
    """util_hier.rpt 의 instance 행을 (들여쓰기, 이름, module, 사용량) 으로 읽습니다."""
    rows = []
    for line in path.read_text().splitlines():
        cells = line.split("|")
        if len(cells) < 12 or not cells[3].strip().isdigit():
            continue
        name = cells[1]
        rows.append({"indent": len(name) - len(name.lstrip(" ")), "name": name.strip(), "module": cells[2].strip(),
                     "lut": int(cells[3]), "lutram": int(cells[5]), "ff": int(cells[7]),
                     "bram": int(cells[8]) + int(cells[9]) / 2, "dsp": int(cells[10])})
    return rows


def blocks(rows):
    """계층 report 를 판정용 블록으로 나눕니다. 각 블록은 그 instance 의 하위 전체를 포함합니다.

    policy      범용 policy solver(grover_ckpt_policy_generic) 하나
    dataset     iteration engine 마다 복제된 dataset · found mask memory 전부
    amplitude   checkpoint amplitude memory 와 읽기 mux (grover_ckpt_mem_parallel)
    datapath    iteration datapath (grover_iter_datapath_parallel)
    control     iteration 제어 FSM (grover_ctrl_fsm_parallel)
    measurement measurement 와 Born sampler (u_measure_verify)
    rest        wrapper 전체에서 위를 뺀 나머지(Bus Interface, BBHT 제어, checkpoint executor 등)
    """
    def first(match):
        for r in rows:
            if match(r):
                return r
        raise ValueError("instance not found")
    total = rows[0]
    picked = {
        "policy": [first(lambda r: r["module"] == "grover_ckpt_policy_generic")],
        "dataset": [r for r in rows if r["name"].startswith("g_oracle_memory[")],
        "amplitude": [first(lambda r: r["module"] == "grover_ckpt_mem_parallel")],
        "datapath": [first(lambda r: r["module"] == "grover_iter_datapath_parallel")],
        "control": [first(lambda r: r["module"] == "grover_ctrl_fsm_parallel")],
        "measurement": [first(lambda r: r["name"] == "u_measure_verify")],
    }
    out = {}
    for block, items in picked.items():
        out[block] = {f: sum(r[f] for r in items) for f in FIELDS}
    out["rest"] = {f: total[f] - sum(out[b][f] for b in picked) for f in FIELDS}
    out["total"] = {f: total[f] for f in FIELDS}
    return out


# policy_cache_report.tcl 이 남기는 policy_cache_memory.csv 에서 셀 primitive 를 셉니다. 분산 RAM 은
# 매크로(RAM32M, RAM64M, RAM64X1D 등)와 그 안의 leaf(RAMD32 등)가 모두 행으로 나오므로 leaf 만 세어
# LUTRAM 으로 쓰인 LUT 수로 봅니다. 이름으로 묶은 logic LUT 는 cache 제어 회로 전체가 아니라 참고값입니다.
LUTRAM_LEAF = ("RAMD32", "RAMS32", "RAMD64E", "RAMS64E")


def cache_primitives(path):
    counts = {}
    if not path.exists():
        return counts
    for row in csv.DictReader(path.open()):
        region = {"candidate_cache": "cache", "memo": "memo"}.get(row["region"])
        if region is None:
            continue
        ref = row["reference"]
        key = ("ramb36" if ref.startswith("RAMB36") else "ramb18" if ref.startswith("RAMB18")
               else "lutram" if ref in LUTRAM_LEAF else "named_lut" if ref.startswith("LUT") else None)
        if key:
            counts[f"{region}_{key}"] = counts.get(f"{region}_{key}", 0) + 1
    for region in ("cache", "memo"):
        for key in ("ramb36", "ramb18", "lutram", "named_lut"):
            counts.setdefault(f"{region}_{key}", 0)
        counts[f"{region}_bram"] = counts[f"{region}_ramb36"] + counts[f"{region}_ramb18"] / 2
    return counts


def collect(synth, out):
    points = []
    for cell in sorted((synth / "synth").iterdir()):
        if not (cell / "resource.json").exists():
            continue
        config = json.loads((cell / "config.json").read_text())
        part = blocks(parse_hier(cell / "util_hier.rpt"))
        resource = json.loads((cell / "resource.json").read_text())
        if part["total"]["lut"] != resource["lut"] or part["total"]["bram"] != resource["bram"]:
            raise ValueError(f"hierarchy total differs from util.rpt: {cell}")
        row = {k: config[k] for k in ("k", "h", "e", "m")}
        for block in ("total",) + BLOCKS:
            row |= {f"{block}_{f}": part[block][f] for f in FIELDS}
        primitives = cache_primitives(cell / "policy_cache_memory.csv")
        row["cache_report"] = bool(primitives)
        for region in ("cache", "memo"):
            for key in ("bram", "ramb36", "ramb18", "lutram", "named_lut"):
                row[f"{region}_{key}"] = primitives.get(f"{region}_{key}", "")
        points.append(row)
        keep = out / "synth" / cell.name
        keep.mkdir(parents=True, exist_ok=True)
        for name in ("config.json", "manifest.json", "adapter.v", "resource.json", "util.rpt", "util_hier.rpt",
                     "policy_cache_memory.csv", "policy_cache_audit_status.txt"):
            if (cell / name).exists():
                shutil.copy(cell / name, keep / name)
    points.sort(key=lambda r: (r["k"], r["h"], r["e"], r["m"]))
    with (out / "points.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(points[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(points)
    return points


# ------------------------------------------------------------------ fit
def cache_bound(k, h):
    """grover_policy_parameterized.sv 의 후보 cache 최악 크기: (항목 수, 항목 bit 폭)."""
    u = k + h + 1
    width = u + max(1, ceil(log2(k + 1))) + 11
    return (h + 1) * sum(comb(u - 1, i) for i in range(k)), width


def cache_tiles(entries, width, lanes=4):
    """후보 cache 를 bank lanes 개(RAMB18 = 512 x 36 bit 이하)에 둘 때의 BRAM tile 수(RAMB36 단위)."""
    depth = (entries + lanes - 1) // lanes + 1
    return lanes * ceil(depth / 512) * ceil(width / 36) / 2


def linear(xs, ys):
    """최소제곱 직선 (절편, 기울기) 와 최대 잔차."""
    a = np.vstack([np.ones(len(xs)), np.array(xs, float)]).T
    coef, *_ = np.linalg.lstsq(a, np.array(ys, float), rcond=None)
    return [float(c) for c in coef], float(np.max(np.abs(a @ coef - np.array(ys, float)))) if len(xs) > 2 else 0.0


def fit(out):
    points = list(csv.DictReader((out / "points.csv").open()))
    for p in points:
        for key in p:
            p[key] = (p[key] == "True") if key == "cache_report" else float(p[key]) if p[key] != "" else None
    base = [p for p in points if p["k"] == 3 and p["h"] == 3]
    model = {"device": DEVICE, "limit": LIMIT, "soc": SOC, "blocks": {}}

    # iteration engines 에만 걸리는 블록: dataset 복제, datapath, 제어. square engines 4 점들로 직선을 맞춥니다.
    m4 = [p for p in base if p["m"] == 4]
    for block in ("dataset", "datapath", "control"):
        model["blocks"][block] = {}
        for f in FIELDS:
            coef, residual = linear([p["e"] for p in m4], [p[f"{block}_{f}"] for p in m4])
            model["blocks"][block][f] = {"intercept": coef[0], "per_iteration_engine": coef[1], "max_residual": residual}

    # amplitude memory: 읽기 mux 는 engine_sweep 식(read port x 736 bit x ceil(bank/4)), BRAM 은 bank x tile 식.
    # 실측과의 차이를 기록만 하고 식은 그대로 씁니다.
    model["blocks"]["amplitude"] = {"check": [
        {"e": p["e"], "m": p["m"], "lut": p["amplitude_lut"], "lut_formula": amplitude_lut(int(p["e"]), int(p["m"])),
         "bram": p["amplitude_bram"], "bram_formula": es.amplitude_tiles(3, int(p["e"]), int(p["m"]))}
        for p in base]}

    # measurement: square engines 4 이하는 기존 sampler, 5 이상은 grover_born_sampler_parallel 입니다.
    # 5 이상 점들로 직선을, 4 이하는 square engines 4 점의 값을 squarer 하나 단가로 나눠 씁니다.
    big = [p for p in base if p["m"] >= 5]
    model["blocks"]["measurement"] = {"parallel": {}, "legacy_m4": {}}
    for f in FIELDS:
        coef, residual = linear([p["m"] for p in big], [p[f"measurement_{f}"] for p in big]) if len(big) >= 2 else ([0, 0], 0)
        model["blocks"]["measurement"]["parallel"][f] = {"intercept": coef[0], "per_square_engine": coef[1],
                                                        "max_residual": residual}
        model["blocks"]["measurement"]["legacy_m4"][f] = float(np.mean([p[f"measurement_{f}"] for p in m4]))
    model["blocks"]["rest"] = {f: float(np.mean([p[f"rest_{f}"] for p in base])) for f in FIELDS}
    model["blocks"]["rest_spread"] = {f: float(np.ptp([p[f"rest_{f}"] for p in base])) for f in FIELDS}

    # policy: iteration engines / square engines 4/4 에서 Checkpoint-Capacity / Lookahead-Shots 만 바꾼 점들.
    # policy 몫에는 policy 블록과 함께, 같은 점의 rest 가 Checkpoint-Capacity / Lookahead-Shots 3/3 보다
    # 늘어난 만큼(checkpoint executor 의 slot 폭 등)을 넣습니다. amplitude memory 의 Checkpoint-Capacity
    # 의존분은 amplitude 식이 따로 셉니다.
    policy = {}
    rows = []
    rest33 = next(p for p in points if (p["k"], p["h"], p["e"], p["m"]) == (3, 3, 4, 4))
    for p in points:
        if p["e"] == 4 and p["m"] == 4:
            k, h = int(p["k"]), int(p["h"])
            entries, width = cache_bound(k, h)
            policy[(k, h)] = {f: p[f"policy_{f}"] + p[f"rest_{f}"] - rest33[f"rest_{f}"] for f in FIELDS}
            rows.append({"k": k, "h": h, "cache_entries": entries, "cache_width": width,
                         "cache_kib": round(entries * width / 8 / 1024, 1),
                         "cache_bram_formula": cache_tiles(entries, width),
                         "cache_bram_measured": p["cache_bram"], "cache_lutram_measured": p["cache_lutram"],
                         "memo_bram_measured": p["memo_bram"], "memo_lutram_measured": p["memo_lutram"],
                         "policy_lut": int(p["policy_lut"]), "policy_ff": int(p["policy_ff"]),
                         "policy_bram": p["policy_bram"]})
    with (out / "policy_cache_kh.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda r: (r["k"], r["h"])))
    model["policy_points"] = [f"{k},{h}" for k, h in sorted(policy)]

    # 실측 점의 예측 오차(블록 식으로 다시 맞춘 값과 synthesis 총합의 차이).
    model["prediction_check"] = []
    for p in points:
        if (int(p["k"]), int(p["h"])) not in policy:
            continue
        est = estimate(model, policy, int(p["e"]), int(p["m"]), int(p["k"]), int(p["h"]))
        model["prediction_check"].append({"point": f"k{int(p['k'])}h{int(p['h'])}e{int(p['e'])}m{int(p['m'])}",
                                          **{f: [p[f"total_{f}"], round(est[f], 1)] for f in FIELDS}})
    (out / "compute_fit.json").write_text(json.dumps(model, indent=2) + "\n")

    # 칸마다 판정: 지원 범위(iteration engines 1~10, square engines 1~9) x 실측한 policy 조합.
    table = []
    for e in SUPPORTED_E:
        for m in SUPPORTED_M:
            for (k, h) in sorted(policy):
                est = estimate(model, policy, e, m, k, h)
                total = {f: est[f] + SOC[f] for f in FIELDS}
                over = [f for f in FIELDS if total[f] > DEVICE[f] * LIMIT[f]]
                table.append({"e": e, "m": m, "k": k, "h": h,
                              **{f"{f}_percent": round(100 * total[f] / DEVICE[f], 1) for f in FIELDS},
                              "feasible": not over, "over": "+".join(over)})
    with (out / "calibrated_feasibility.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(table[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(table)
    return model, rows, table


def amplitude_lut(e, m):
    b = es.banks(e, m)
    return max(e, max(m, 4)) * es.AMP_W * -(-b // 4)


def estimate(model, policy, e, m, k, h):
    """wrapper 하나의 사용량 추정(SoC 제외). policy 는 실측한 (k, h) 만 받습니다."""
    blocks = model["blocks"]
    est = {}
    for f in FIELDS:
        value = blocks["rest"][f] + policy[(k, h)][f]
        for block in ("dataset", "datapath", "control"):
            c = blocks[block][f]
            value += c["intercept"] + c["per_iteration_engine"] * e
        if m >= 5:
            c = blocks["measurement"]["parallel"][f]
            value += c["intercept"] + c["per_square_engine"] * m
        else:
            # 기존 sampler 는 square engines 4 실측을 squarer 수에 비례해 줄입니다(squarer 가 대부분).
            value += blocks["measurement"]["legacy_m4"][f] * (m / 4 if f in ("lut", "ff", "dsp") else 1)
        if f == "lut":
            value += amplitude_lut(e, m)
        elif f == "bram":
            value += es.amplitude_tiles(k, e, m)
        # amplitude 블록의 FF(읽기 bank 선택 register 등)는 수백 개라 넣지 않습니다.
        est[f] = value
    return est


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["collect", "fit"])
    parser.add_argument("--synth", type=Path, help="collect: engine_sweep.py synth --out directory")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if args.stage == "collect":
        print(len(collect(args.synth.resolve(), out)), "synthesis points")
    else:
        model, rows, table = fit(out)
        print(json.dumps(model["prediction_check"], indent=1))


if __name__ == "__main__":
    sys.exit(main())
