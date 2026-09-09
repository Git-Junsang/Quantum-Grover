#!/usr/bin/env python3
"""
policy 게이트 -- compute 이득을 세기 전에 policy 복잡도로 후보를 거릅니다.

## 왜 이게 먼저인가

makespan 표만 보면 compute 를 줄인 후보가 이겨 보입니다. 그런데 policy 결정이
compute 뒤에 못 숨으면 **연산은 끝났는데 결정을 기다리는 구간**이 생기고, 줄인
compute 가 그대로 상쇄됩니다. K4/H4 보드 telemetry 가 그 구간을 샷당 75.69 사이클로
찍어 두었습니다. 따라서 순서는 이렇습니다.

    1. 후보의 policy 복잡도를 먼저 잰다
    2. K4/H4 보다 높으면 버린다
    3. 살아남은 것만 compute 이득을 따진다

## 은닉 모델 (보드로 검증)

RTL 은 `AUTO_SPEC_ENABLE=1` 의 one-shot-ahead Shadow-J 라 결정 i 는 **직전 샷**이
도는 동안만 풀 수 있습니다. 그래서

    노출_i = max(0, policy_i - (직전 샷 compute + 샷 고정비) / E)

E 는 엔진 수입니다. 엔진이 늘면 샷 하나가 벽시계로 더 빨리 끝나므로 **숨을 시간이
그만큼 줄어듭니다.** 이것이 다중 엔진이 policy 를 악화시키는 기전입니다.

K4/H4 로 검증하면 338,041 사이클이 나옵니다. 보드 실측 276,027 대비 +22.5% 이므로
이 모델은 **보수적(과대평가)** 입니다. 후보를 살려 주는 쪽이 아니라 죽이는 쪽으로
틀리므로, 통과한 후보는 신뢰할 수 있습니다.

## 보정 상수 (전부 보드 계측에서)

    결정당 action  79.46          policy_actions / (cold+spec solve)
    action 당 사이클 4.872        policy_cycles / policy_actions
    반복당 사이클  1,051.7        250쌍 per-seed 회귀
    샷 고정비      919.3          같은 회귀
"""
from __future__ import annotations

import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from online_policy import make_scorer, run_policy  # noqa: E402
from policy_work import (  # noqa: E402
    BOARD_ACT_PER_SOLVE,
    BOARD_CYC_PER_ACTION,
    CYC_PER_ITER,
    measure,
)

SHOT_OVH = 919.3
SHOTS = 3647
BOARD_ITER = 4247
BOARD_CYCLES = 7796908
BOARD_STALL = 276027


def exposed_stall(costs, actions, cyc_per_action, engines):
    """one-shot-ahead 은닉. 엔진이 늘면 은닉 창이 그만큼 줄어듭니다."""
    total = 0.0
    for index in range(len(actions)):
        policy = actions[index] * cyc_per_action
        if index == 0:
            budget = 0.0  # 첫 결정은 앞에 도는 것이 없습니다
        else:
            budget = (costs[index - 1] * CYC_PER_ITER + SHOT_OVH) / engines
        total += max(0.0, policy - budget)
    return total


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "out", "logical_traces.json"), encoding="utf-8") as h:
        traces = json.load(h)
    all_requests = [[int(v) for v in t["requested_j"]] for t in traces]

    # 기준선에서 보정 배율을 뽑습니다.
    scorer = make_scorer(4)
    base_costs, base_actions = [], []
    for requests in all_requests:
        _, steps = run_policy(requests, 4, 4, scorer)
        _, acts = measure(requests, 4, 4)
        base_costs.append([s["physical"] for s in steps])
        base_actions.append(acts)
    model_apd = sum(sum(a) for a in base_actions) / sum(len(a) for a in base_actions)
    scale = BOARD_ACT_PER_SOLVE / model_apd
    cpa = scale * BOARD_CYC_PER_ACTION

    check = sum(
        exposed_stall(c, a, cpa, 1) for c, a in zip(base_costs, base_actions)
    )
    print("=== 모델 검증 (K4/H4)")
    print(f"  모델 결정당 action {model_apd:.3f} -> 보정 {scale:.3f}, action 당 {cpa:.2f} 사이클")
    print(f"  노출 stall 모델 {check:,.0f}  보드 {BOARD_STALL:,}  ({100*(check/BOARD_STALL-1):+.1f}%, 보수적)")

    # 후보. (이름, K, H, 엔진, makespan 반복, 분할)
    # 은닉 엔진 수(hide_e)는 "결정 하나가 숨을 수 있는 시간이 몇 분의 일로
    # 줄어드는가" 입니다. Family 1 은 엔진 2벌이 **같은 요청 열**을 나눠 처리하므로
    # 결정이 벽시계로 두 배 빨리 와서 창이 반으로 줄어듭니다. Family 2 는 track
    # 마다 자기 엔진과 자기 policy 를 가지므로 track 안에서는 창이 그대로입니다.
    cands = [
        ("K4/H4 (기준선)", 4, 4, 1, 4247, "single"),
        ("K4/H6 (단일)", 4, 6, 1, 4125, "single"),
        ("K3/H4 (단일)", 3, 4, 1, 4230, "single"),
        ("K5/H4 (단일)", 5, 4, 1, 4049, "single"),
        ("K6/H4 (단일)", 6, 4, 1, 4042, "single"),
        ("F1 C3+R2 선택적투기", 3, 4, 2, 4094, "single"),
        ("F1 C4+R2 선택적투기", 4, 4, 2, 4065, "single"),
        ("F1 C5+R2 선택적투기", 5, 4, 2, 4058, "single"),
        ("F2 parity K2+K2", 2, 4, 1, 4216, "parity"),
        ("F2 parity K3+K2", 3, 4, 1, 4102, "parity32"),
        ("F2 parity K3+K3", 3, 4, 1, 4050, "parity"),
    ]

    rows = []
    for name, capacity, horizon, engines, makespan, split in cands:
        costs_all, acts_all = [], []
        for requests in all_requests:
            if split == "single":
                seqs = [requests]
            elif split == "parity":
                seqs = [requests[0::2], requests[1::2]]
            else:  # A=K3, B=K2 -- 용량이 다르므로 따로
                seqs = [requests[0::2], requests[1::2]]
            for pos, seq in enumerate(seqs):
                if not seq:
                    continue
                cap = capacity
                if split == "parity32" and pos == 1:
                    cap = 2
                sc = make_scorer(cap)
                _, steps = run_policy(seq, cap, horizon, sc)
                _, acts = measure(seq, cap, horizon)
                costs_all.append([s["physical"] for s in steps])
                acts_all.append(acts)
        if split == "single" and engines == 1:
            # 단일 엔진은 online policy 가 실제로 낸 작업량이 곧 makespan 입니다.
            # offline 최적을 쓰면 정책이 못 내는 값을 쓰게 됩니다.
            makespan = sum(sum(c) for c in costs_all)
        decisions = sum(len(a) for a in acts_all)
        actions = sum(sum(a) for a in acts_all)
        apd = actions / decisions
        stall = sum(
            exposed_stall(c, a, cpa, engines) for c, a in zip(costs_all, acts_all)
        )
        cycles = makespan * CYC_PER_ITER + SHOTS * SHOT_OVH + stall
        rows.append(
            dict(
                name=name, K=capacity, H=horizon, E=engines,
                real_e=2 if name.startswith(("F1", "F2")) else 1,
                makespan=makespan,
                decisions=decisions, actions=actions, act_per_dec=apd,
                policy_ratio=apd / (BOARD_ACT_PER_SOLVE / scale),
                stall=stall, cycles=cycles,
            )
        )

    base = rows[0]
    print("\n=== 1단계: policy 복잡도 게이트")
    print(f"{'후보':<22}{'K':>2}{'E':>2}{'결정당 action':>13}{'vs 기준선':>10}{'판정':>7}")
    print("-" * 60)
    for r in rows:
        ratio = r["act_per_dec"] / base["act_per_dec"]
        r["pass"] = ratio <= 1.0
        verdict = "기준선" if r is base else ("통과" if r["pass"] else "탈락")
        print(
            f"{r['name']:<22}{r['K']:>2}{r['real_e']:>2}"
            f"{r['act_per_dec']*scale:>13.2f}{ratio:>9.2f}x{verdict:>7}"
        )

    print("\n=== 2단계: 통과한 후보만 사이클로")
    print(
        f"{'후보':<22}{'makespan':>9}{'노출 stall':>11}{'총 사이클':>12}"
        f"{'vs 보드 7,796,908':>19}"
    )
    print("-" * 74)
    for r in rows:
        if not r["pass"] and r is not base:
            print(f"{r['name']:<22}{'':>9}{'':>11}{'-- policy 게이트 탈락 --':>31}")
            continue
        delta = 100 * (r["cycles"] / BOARD_CYCLES - 1)
        print(
            f"{r['name']:<22}{r['makespan']:>9,}{r['stall']:>11,.0f}"
            f"{r['cycles']:>12,.0f}{delta:>18.2f}%"
        )

    path = os.path.join(here, "out", "policy_gate.csv")
    with open(path, "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(
            h,
            fieldnames=["name", "K", "H", "E", "real_e", "makespan", "decisions", "actions",
                        "act_per_dec", "policy_ratio", "stall", "cycles", "pass"],
        )
        w.writeheader()
        w.writerows(rows)
    print(f"\nraw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
