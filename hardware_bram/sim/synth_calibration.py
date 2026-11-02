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
        # policy_cache_memory.csv(점당 최대 2 MB)는 cache · memo 의 primitive 수만 points.csv 에 남기고 복사하지 않습니다.
        for name in ("config.json", "manifest.json", "adapter.v", "resource.json", "util.rpt", "util_hier.rpt",
                     "policy_cache_audit_status.txt"):
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


# 칸마다 "들어가는 것 중 가장 좋은" policy 조합을 고를 때의 순서. 100 workloads K/H sweep 의 기준점
# (iteration engines 9 / square engines 7) 총 cycle 이 작은 순서이고, 다른 E/M 에서도 순위가 거의 같았습니다.
RANK_TABLE = es.ROOT / "hardware_bram/results/2026-10-29_checkpoint_sweep/workloads100/e9m7/anchor_table.csv"


def fit(out):
    points = list(csv.DictReader((out / "points.csv").open()))
    for p in points:
        for key in p:
            p[key] = (p[key] == "True") if key == "cache_report" else float(p[key]) if p[key] != "" else None
    base = {(int(p["e"]), int(p["m"])): p for p in points if p["k"] == 3 and p["h"] == 3}
    grid = {(int(p["k"]), int(p["h"])): p for p in points if p["e"] == 4 and p["m"] == 4}

    # policy: iteration engines / square engines 4/4 에서 Checkpoint-Capacity / Lookahead-Shots 만 바꾼 점들.
    rows = []
    for (k, h), p in sorted(grid.items()):
        entries, width = cache_bound(k, h)
        rows.append({"k": k, "h": h, "cache_entries": entries, "cache_width": width,
                     "cache_kib": round(entries * width / 8 / 1024, 1),
                     "cache_bram_formula": cache_tiles(entries, width),
                     "cache_bram_measured": p["cache_bram"], "cache_lutram_measured": p["cache_lutram"],
                     "memo_bram_measured": p["memo_bram"], "memo_lutram_measured": p["memo_lutram"],
                     "policy_lut": int(p["policy_lut"]), "policy_ff": int(p["policy_ff"]),
                     "policy_bram": p["policy_bram"], "wrapper_lut": int(p["total_lut"]),
                     "wrapper_bram": p["total_bram"]})
    with (out / "policy_cache_kh.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    model = Model(base, grid)
    report = {"device": DEVICE, "limit": LIMIT, "soc": SOC, "policy_points": [f"{k},{h}" for k, h in sorted(grid)],
              "measured_engine_points": [f"{e},{m}" for e, m in sorted(base)],
              "leave_one_out": model.leave_one_out()}
    (out / "compute_fit.json").write_text(json.dumps(report, indent=2) + "\n")

    # 칸마다 판정: 지원 범위(iteration engines 1~10, square engines 1~9) x 실측한 policy 조합.
    table = []
    for e in SUPPORTED_E:
        for m in SUPPORTED_M:
            for (k, h) in sorted(grid):
                est = model.total(e, m, k, h)
                total = {f: est[f] + SOC[f] for f in FIELDS}
                over = [f for f in FIELDS if total[f] > DEVICE[f] * LIMIT[f]]
                table.append({"e": e, "m": m, "k": k, "h": h,
                              **{f"{f}_percent": round(100 * total[f] / DEVICE[f], 1) for f in FIELDS},
                              "feasible": not over, "over": "+".join(over),
                              "engine_source": "measured" if (e, m) in base else "estimated"})
    with (out / "calibrated_feasibility.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(table[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(table)

    # 칸마다 들어가는 policy 조합 중 가장 좋은 것(RANK_TABLE 의 총 cycle 순).
    cycles = {(int(r["k"]), int(r["h"])): int(r["sample_cycles"]) for r in csv.DictReader(RANK_TABLE.open())}
    order = sorted(grid, key=lambda kh: cycles[kh])
    fits = {(r["e"], r["m"], r["k"], r["h"]): r["feasible"] for r in table}
    best = []
    for e in SUPPORTED_E:
        for m in SUPPORTED_M:
            choice = next((kh for kh in order if fits[(e, m, *kh)]), None)
            best.append({"e": e, "m": m, "best_k": choice[0] if choice else "", "best_h": choice[1] if choice else "",
                         "rank_cycle_gap_percent": round(100 * (cycles[choice] / cycles[order[0]] - 1), 2)
                         if choice else ""})
    with (out / "calibrated_best.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(best[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(best)
    report["rank_order"] = [f"{k},{h}" for k, h in order]
    (out / "compute_fit.json").write_text(json.dumps(report, indent=2) + "\n")
    return report, rows, table


class Model:
    """Checkpoint-Capacity / Lookahead-Shots 3/3 의 연산부 실측과 4/4 의 policy 실측을 합치는 사용량 모델.

    연산부(K3H3) 사용량은 synthesis 한 칸이면 그 실측 총합을 그대로 쓰고, 아니면 세 부분을 더합니다.

      linear     dataset 복제 + iteration 제어: iteration engines 에 비례(실측 직선)
      crossbar   amplitude 읽기 · 쓰기 mux + iteration datapath: bank 구조가 같은 실측 칸의 값.
                 bank 수 = max(iteration engines, square engines, 4) 이고, bank 가 iteration engines 와
                 같을 때와 square engines 때문에 더 많을 때를 구분합니다. LUT 는 2 의 거듭제곱 여부에 따라
                 크게 달라 engine 수로 보간하지 않습니다.
      sampler    measurement + 나머지(Bus Interface, BBHT 제어 등): square engines 별 실측. 4 이하는 기존
                 sampler, 5 이상은 grover_born_sampler_parallel 입니다.

    Checkpoint-Capacity / Lookahead-Shots 를 바꾸면 iteration engines / square engines 4/4 에서 잰
    policy + 나머지의 증가분과, amplitude memory BRAM 의 Checkpoint-Capacity 의존분(식)을 더합니다.
    """

    def __init__(self, base, grid, exclude=None):
        self.base = {key: p for key, p in base.items() if key != exclude}
        self.grid = grid
        pts = list(self.base.values())
        self.linear = {f: linear([p["e"] for p in pts], [p[f"dataset_{f}"] + p[f"control_{f}"] for p in pts])[0]
                       for f in FIELDS}
        self.policy33 = {f: float(np.mean([p[f"policy_{f}"] for p in pts])) for f in FIELDS}

    # bank 구조: (iteration engines, bank 수, 새 sampler 여부)
    @staticmethod
    def shape(e, m):
        return e, es.banks(e, m), m >= 5

    def crossbar(self, e, m, f):
        if f == "bram":
            return float(es.amplitude_tiles(3, e, m))
        if f == "dsp":
            return 0.0
        same = [p for (pe, pm), p in self.base.items() if self.shape(pe, pm) == self.shape(e, m)]
        if same:
            return float(np.mean([p[f"amplitude_{f}"] + p[f"datapath_{f}"] for p in same]))
        b = es.banks(e, m)
        # 같은 bank 수의 실측 중 가장 가까운 것: bank = iteration engines 인 칸을 먼저 보고(E < 4 는 bank 4 의
        # 실측을 상한으로), 새 sampler 가 붙는 경우에는 같은 bank 의 새 sampler 칸이 있으면 그것을 씁니다.
        cands = [p for (pe, pm), p in self.base.items() if es.banks(pe, pm) == b and (pm >= 5) == (m >= 5)]
        cands = cands or [p for (pe, pm), p in self.base.items() if es.banks(pe, pm) == b]
        if not cands:
            raise KeyError(f"no measured point with {b} banks")
        return float(max(p[f"amplitude_{f}"] + p[f"datapath_{f}"] for p in cands))

    def sampler(self, m, f):
        rows = {}
        for (pe, pm), p in self.base.items():
            rows.setdefault(pm, []).append(p[f"measurement_{f}"] + p[f"rest_{f}"])
        table = {mm: float(np.mean(v)) for mm, v in rows.items()}
        if f == "dsp":
            return 64.0 * m
        if m in table:
            return table[m]
        same = sorted(mm for mm in table if (mm >= 5) == (m >= 5))
        lower = [mm for mm in same if mm < m]
        upper = [mm for mm in same if mm > m]
        if lower and upper:
            a, b = lower[-1], upper[0]
            return table[a] + (table[b] - table[a]) * (m - a) / (b - a)
        # 4 이하 범위의 끝(square engines 1~2)은 가장 가까운 실측을 그대로 씁니다.
        near = min(same or table, key=lambda mm: abs(mm - m))
        if m >= 5 and len(same) >= 2:
            a, b = same[-2], same[-1]
            return table[b] + (table[b] - table[a]) * (m - b) / (b - a)
        return table[near]

    def engine(self, e, m):
        """연산부 + K3H3 policy 의 wrapper 사용량(SoC 제외)과 출처."""
        if (e, m) in self.base:
            p = self.base[(e, m)]
            return {f: p[f"total_{f}"] for f in FIELDS}, "measured"
        out = {}
        for f in FIELDS:
            c = self.linear[f]
            out[f] = c[0] + c[1] * e + self.crossbar(e, m, f) + self.sampler(m, f) + self.policy33[f]
        return out, "estimated"

    def total(self, e, m, k, h):
        value, _ = self.engine(e, m)
        p, p33 = self.grid[(k, h)], self.grid[(3, 3)]
        out = {}
        for f in FIELDS:
            # iteration engines / square engines 4/4 에서 잰 wrapper 총합의 차이를 그대로 씁니다. policy 블록만의
            # 차이를 쓰면 다른 블록이 synthesis 마다 1~2천 LUT 씩 오르내리는 몫이 빠지거나 겹쳐, 실측점도 재현되지
            # 않았습니다(K5H6: 블록 합 차이 11,901 대 총합 차이 9,655). BRAM 은 amplitude memory 의
            # Checkpoint-Capacity 몫을 4/4 의 식 값에서 대상 E/M 의 식 값으로 바꿔 끼웁니다.
            delta = p[f"total_{f}"] - p33[f"total_{f}"]
            if f == "bram":
                delta += (es.amplitude_tiles(k, e, m) - es.amplitude_tiles(3, e, m)
                          - es.amplitude_tiles(k, 4, 4) + es.amplitude_tiles(3, 4, 4))
            out[f] = value[f] + delta
        return out

    def leave_one_out(self):
        """실측한 연산부 칸을 하나씩 빼고 나머지로 그 칸을 추정했을 때의 오차."""
        checks = []
        for key, p in sorted(self.base.items()):
            try:
                est, _ = Model(self.base, self.grid, exclude=key).engine(*key)
            except KeyError as error:
                checks.append({"point": f"e{key[0]}m{key[1]}", "note": str(error)})
                continue
            checks.append({"point": f"e{key[0]}m{key[1]}",
                           **{f: [p[f"total_{f}"], round(est[f], 1)] for f in FIELDS}})
        return checks


# ------------------------------------------------------------------ kh_range
# Checkpoint-Capacity / Lookahead-Shots 의 policy 비용을 synthesis 전에 예상하는 식. iteration engines / square
# engines 4/4 에서 잰 점들로 맞췄고, K7H9(BRAM 이 바닥나 memo table 이 LUTRAM 으로 밀려난 점)는 뺐습니다.
# 실측점 하나씩 빼고 맞춘 예측 오차는 rms 약 900, 최대 약 1,700 LUT 입니다.
POLICY_LUT_COEF = (2014.9, 1468.0, 287.0)

# Vivado 가 후보 cache bank 를 BRAM 으로 쌓는 규칙: bank 깊이를 2 의 거듭제곱으로 올리고, 그 깊이에서 RAMB18
# 하나가 담는 bit 수로 항목 폭을 나눕니다(2K 이하 깊이는 parity 를 써 36 / 18 / 9 bit). 실측 12점 중 10점이
# 정확히 맞고 2점은 2 tile 많게(안전한 쪽으로) 나옵니다. 항목이 bank 당 64 이하이면 LUTRAM 으로 갑니다.
RAMB18_BITS = {512: 36, 1024: 18, 2048: 9, 4096: 4, 8192: 2, 16384: 1, 32768: 0.5, 65536: 0.25,
               131072: 0.125, 262144: 0.0625, 524288: 0.03125, 1048576: 0.015625, 2097152: 0.0078125}


def policy_lut_delta(k, h):
    a, b, c = POLICY_LUT_COEF
    return a * (k - 3) + b * (h - 3) + c * (k - 3) * (h - 3)


def cache_bram_rule(k, h, lanes=4):
    entries, width = cache_bound(k, h)
    depth = (entries + lanes - 1) // lanes + 1
    if entries <= 64 * lanes:
        return 0.0
    d2 = max(512, 1 << (depth - 1).bit_length())
    return lanes * ceil(width / RAMB18_BITS[d2]) / 2


def kh_range(out, k_range=range(3, 11), h_range=range(3, 11)):
    """iteration engines / square engines 마다 200T 에 들어가는 Checkpoint-Capacity x Lookahead-Shots 를 예상합니다.

    resource 만 봅니다(cycle 은 보지 않음). 연산부는 Model.engine(K3H3 실측 또는 블록 추정), policy 는 위 두 식,
    amplitude memory 의 Checkpoint-Capacity 의존분은 engine_sweep.amplitude_tiles 식입니다. DSP 는 square engines
    만으로 정해지고, FF 는 이 범위에서 한도의 30% 를 넘지 않아 판정에 넣지 않습니다.
    """
    points = list(csv.DictReader((out / "points.csv").open()))
    for p in points:
        for key in p:
            p[key] = (p[key] == "True") if key == "cache_report" else float(p[key]) if p[key] != "" else None
    base = {(int(p["e"]), int(p["m"])): p for p in points if p["k"] == 3 and p["h"] == 3}
    grid = {(int(p["k"]), int(p["h"])): p for p in points if p["e"] == 4 and p["m"] == 4}
    exact = {(int(p["e"]), int(p["m"]), int(p["k"]), int(p["h"])): p for p in points}
    model = Model(base, grid)
    cap = {f: DEVICE[f] * LIMIT[f] for f in FIELDS}
    rows, checks = [], []
    for e in SUPPORTED_E:
        for m in SUPPORTED_M:
            engine, source = model.engine(e, m)
            for k in k_range:
                for h in h_range:
                    predicted = {
                        "lut": engine["lut"] + SOC["lut"] + policy_lut_delta(k, h),
                        "bram": (engine["bram"] + SOC["bram"] + cache_bram_rule(k, h)
                                 + es.amplitude_tiles(k, e, m) - es.amplitude_tiles(3, e, m)),
                        "dsp": engine["dsp"] + SOC["dsp"]}
                    # 그 조합을 synthesis 했으면 예상 대신 실측(+SoC)을 씁니다.
                    point = exact.get((e, m, k, h))
                    used = ({f: point[f"total_{f}"] + SOC[f] for f in ("lut", "bram", "dsp")} if point else predicted)
                    over = [f for f in ("lut", "bram", "dsp") if used[f] > cap[f]]
                    rows.append({"e": e, "m": m, "k": k, "h": h,
                                 **{f"{f}_percent": round(100 * used[f] / DEVICE[f], 1) for f in ("lut", "bram", "dsp")},
                                 "feasible": not over, "over": "+".join(over), "engine_source": source,
                                 "source": "synthesized" if point else "predicted",
                                 "lut_predicted_percent": round(100 * predicted["lut"] / DEVICE["lut"], 1),
                                 "bram_predicted_percent": round(100 * predicted["bram"] / DEVICE["bram"], 1)})
                    if point and not (k == 3 and h == 3):
                        # 예상 식이 실측을 얼마나 맞히는지. E4M4 의 점들은 policy 식을 맞춘 점이라 따로 표시합니다.
                        pred_over = [f for f in ("lut", "bram", "dsp") if predicted[f] > cap[f]]
                        checks.append({"e": e, "m": m, "k": k, "h": h,
                                       "kind": "fit point" if (e, m) == (4, 4) else "combined check",
                                       "lut_measured": int(used["lut"]), "lut_predicted": int(round(predicted["lut"])),
                                       "lut_error": int(round(predicted["lut"] - used["lut"])),
                                       "bram_measured": used["bram"], "bram_predicted": predicted["bram"],
                                       "bram_error": predicted["bram"] - used["bram"],
                                       "feasible_measured": not over, "feasible_predicted": not pred_over})
    with (out / "kh_range.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    if checks:
        with (out / "prediction_check.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(checks[0]), lineterminator="\n")
            writer.writeheader()
            writer.writerows(sorted(checks, key=lambda c: (c["kind"], -c["e"], c["m"], c["k"], c["h"])))
    return rows


# kh_heatmap 의 가로 범위(사용자 지정). 3/3 에서도 넘치는 조합도 넣고 빗금으로 표시합니다.
HEATMAP_E = range(4, 11)
HEATMAP_M = range(1, 9)


def kh_heatmap(out):
    """iteration engines / square engines(가로) x Checkpoint-Capacity / Lookahead-Shots(세로) 의 200T 가능 범위.

    가로는 HEATMAP_E x HEATMAP_M 의 모든 조합을 iteration engines 별로 묶어 square engines 순으로 둡니다. 세로는 Checkpoint-Capacity 별로 묶어 Lookahead-Shots
    순입니다. 칸 색은 가장 빠듯한 자원(LUT 75%, BRAM 90%, DSP 90% 한도)의 한도 대비 사용률이고, 여유가 클수록
    빨강입니다. cycle 은 보지 않습니다.
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import Normalize
    rows = list(csv.DictReader((out / "kh_range.csv").open()))
    cell = {(int(r["e"]), int(r["m"]), int(r["k"]), int(r["h"])): r for r in rows}
    ks = sorted({int(r["k"]) for r in rows})
    hs = sorted({int(r["h"]) for r in rows})
    kh = [(k, h) for k in ks for h in hs]
    em = [(e, m) for e in HEATMAP_E for m in HEATMAP_M]
    cap_percent = {f: 100 * LIMIT[f] for f in ("lut", "bram", "dsp")}
    tight = np.full((len(kh), len(em)), np.nan)
    fits = np.zeros((len(kh), len(em)), bool)
    for x, (e, m) in enumerate(em):
        for y, (k, h) in enumerate(kh):
            r = cell[(e, m, k, h)]
            tight[y, x] = max(float(r[f"{f}_percent"]) / cap_percent[f] for f in cap_percent) * 100
            fits[y, x] = r["feasible"] == "True"
    fig, ax = plt.subplots(figsize=(24, 18))
    cmap = plt.get_cmap("rainbow_r").copy()
    norm = Normalize(vmin=50, vmax=100, clip=True)
    image = ax.imshow(np.ma.masked_where(~fits, tight), origin="lower", cmap=cmap, norm=norm, aspect="auto")
    hatches = {"lut": "///", "bram": "\\\\\\", "dsp": "...", "lut+bram": "xxx"}
    for x, (e, m) in enumerate(em):
        for y, (k, h) in enumerate(kh):
            r = cell[(e, m, k, h)]
            if not fits[y, x]:
                ax.add_patch(plt.Rectangle((x - .5, y - .5), 1, 1, facecolor="0.88", edgecolor="0.45",
                                           hatch=hatches.get(r["over"], "xxx"), lw=0))
            if r["source"] == "synthesized":
                ax.plot(x, y, "o", ms=5, mfc="black", mec="white", mew=0.8)
    import engine_sweep
    engine_sweep.outline_inset(ax, fits, 0.0, color="black", lw=2.2)
    for y in range(len(hs), len(kh), len(hs)):
        ax.axhline(y - .5, color="white", lw=1.6)
    groups = [x for x in range(1, len(em)) if em[x][0] != em[x - 1][0]]
    for x in groups:
        ax.axvline(x - .5, color="white", lw=1.6)
    ax.set_xticks(range(len(em)), [f"{e}/{m}" + ("*" if cell[(e, m, ks[0], hs[0])]["engine_source"] == "measured" else "")
                                   for e, m in em], rotation=90, fontsize=8)
    ax.set_yticks(range(len(kh)), [f"{k}/{h}" for k, h in kh], fontsize=7)
    ax.set_xlabel("iteration engines / square engines   (* = engine pair synthesized at capacity 3 / lookahead 3)")
    ax.set_ylabel("checkpoint capacity / lookahead shots")
    ax.set_title("200T FIT BY RESOURCES ONLY (no cycles): checkpoint capacity x lookahead shots for each engine pair\n"
                 "color: tightest of LUT (limit 75%), BRAM (90%), DSP (90%) as a share of its limit; red = more "
                 "headroom; SoC included, timing excluded\n"
                 "hatched grey: over the limit (/// LUT, \\\\ BRAM, xxx both);  black line: boundary of the fitting "
                 "region;  dot: this exact combination synthesized\n"
                 "other cells predicted: engine blocks from synthesized points + policy cost fitted on synthesized "
                 "capacity / lookahead points", fontsize=9)
    bar = fig.colorbar(image, ax=ax, shrink=0.5, label="tightest resource, % of its limit")
    fig.tight_layout()
    fig.savefig(out / "feasibility_heatmap.png", dpi=150)
    fig.savefig(out / "feasibility_heatmap.svg")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["collect", "fit", "kh_range", "kh_heatmap"])
    parser.add_argument("--synth", type=Path, help="collect: engine_sweep.py synth --out directory")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if args.stage == "collect":
        print(len(collect(args.synth.resolve(), out)), "synthesis points")
    elif args.stage == "kh_range":
        rows = kh_range(out)
        print(len(rows), "rows ->", out / "kh_range.csv")
    elif args.stage == "kh_heatmap":
        kh_heatmap(out)
        print("->", out / "feasibility_heatmap.png")
    else:
        report, rows, table = fit(out)
        for check in report["leave_one_out"]:
            print(check["point"], check.get("lut", check.get("note")))


if __name__ == "__main__":
    sys.exit(main())
