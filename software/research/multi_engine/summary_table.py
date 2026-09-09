#!/usr/bin/env python3
"""
최종 비교표 (연구 지시 15절 형식).

앞선 실험들의 결과를 한 표로 모읍니다. 새로 계산하는 것은 사이클 환산뿐이고,
물리 반복과 makespan 은 전부 앞 단계 산출물에서 가져옵니다.

## 등급 (13절)

MEASURED   2026-09-01 보드 실측. frozen K4/H4 행과 Normal 행
ESTIMATED  그 밖의 전부. SW 시뮬레이션 결과이거나, 아래 사이클 모델을 통과한 값

## 사이클 모델

Normal 실행(policy 없음) 다섯 조건에서 최소제곱으로 뽑았습니다. 오차 0.3% 이내.

    cycles = 1,031.7 x (물리 반복) + 1,337.1 x (샷 수) + (policy 노출 지연)

policy 노출 지연은 아키텍처마다 다릅니다. frozen K4/H4 는 계측값이 있고
(6,416,368 사이클 = 요청당 1,759), Family 1/2 의 policy RTL 은 아직 없으므로
요청당 지연 d 를 훑는 민감도로만 냅니다. **이 값을 actual RTL latency 라고
부르지 않습니다.**
"""
from __future__ import annotations

import csv
import json
import os
import sys

CYC_PER_ITER = 1031.7
CYC_PER_SHOT = 1337.1
REQUESTS = 3647          # frozen trace 의 논리 요청 총수
NORMAL_ITER = 14883
NORMAL_CYCLES = 20229755
BASE_ITER = 4134         # frozen K4/H4 보드 실측
BASE_CYCLES = 13824806
BASE_STALL = 6416368

# (이름, family, H, checkpoint 구성, 엔진, 물리작업, makespan(반복), 이용률, 등급, 비고)
ROWS = [
    ("Normal BBHT (checkpoint 없음)", "-", "-", "없음", 1,
     NORMAL_ITER, NORMAL_ITER, 100.0, "MEASURED", "보드 실측"),
    ("frozen K4/H4 (정본)", "baseline", 4, "K4", 1,
     BASE_ITER, BASE_ITER, 100.0, "MEASURED", "보드 실측. 비교 기준"),
    ("골든 모델 endpoint-only", "baseline", "n/a", "K4", 1,
     5850, 5850, 100.0, "ESTIMATED", "source 파괴 + 중간 적재 없음"),
    ("우리 restricted-B online H4", "baseline", 4, "K4", 1,
     4214, 4214, 100.0, "ESTIMATED", "정본 재현 +1.94%"),
    ("우리 restricted-B online H6", "baseline", 6, "K4", 1,
     4125, 4125, 100.0, "ESTIMATED", "정본 재현 -0.22%"),
    ("offline OPT endpoint-only", "bound", "∞", "K4", 1,
     5850, 5850, 100.0, "ESTIMATED", "그 계급의 하한"),
    ("offline OPT source 보존", "bound", "∞", "K4", 1,
     4640, 4640, 100.0, "ESTIMATED", "중간 적재 없음"),
    ("offline OPT bridge (K4)", "bound", "∞", "K4", 1,
     4083, 4083, 100.0, "ESTIMATED", "**정본이 속한 계급의 천장**"),
    ("offline OPT bridge (K3)", "bound", "∞", "K3", 1,
     4230, 4230, 100.0, "ESTIMATED", "Family 1 의 C3 예산"),
    ("offline OPT bridge (K5)", "bound", "∞", "K5", 1,
     4049, 4049, 100.0, "ESTIMATED", "K 를 늘려도 0.8%"),
    ("offline OPT bridge (K6)", "bound", "∞", "K6", 1,
     4042, 4042, 100.0, "ESTIMATED", "포화"),
    ("F1 전가시성 낙관 (C4)", "Family 1", 4, "C4", 2,
     4083, 2621, 77.9, "ESTIMATED", "동시 job 이 서로를 본다고 침. 도달 불가"),
    ("F1 가시성제약 + 즉시refill (C3)", "Family 1", 4, "C3+R2", 2,
     6987, 4224, 82.7, "ESTIMATED", "F1-2 work-conserving"),
    ("F1 가시성제약 + 즉시refill (C4)", "Family 1", 4, "C4+R2", 2,
     6863, 4157, 82.5, "ESTIMATED", ""),
    ("F1 가시성제약 + 즉시refill (C5)", "Family 1", 4, "C5+R2", 2,
     6794, 4126, 82.3, "ESTIMATED", ""),
    ("F1 가시성제약 + 선택적투기 (C3)", "Family 1", 4, "C3+R2", 2,
     6398, 4094, 78.1, "ESTIMATED", "지시 2절 예산 그대로"),
    ("F1 가시성제약 + 선택적투기 (C4)", "Family 1", 4, "C4+R2", 2,
     6386, 4065, 78.5, "ESTIMATED", "**Family 1 best**"),
    ("F1 가시성제약 + 선택적투기 (C5)", "Family 1", 4, "C5+R2", 2,
     6421, 4058, 79.1, "ESTIMATED", "5-state 최대 해석"),
    ("F2 parity A=K2 B=K2", "Family 2", "∞", "K2+K2", 2,
     6573, 4216, 78.0, "ESTIMATED", "track 별 offline. 도달 불가 낙관"),
    ("F2 parity A=K3 B=K2", "Family 2", "∞", "K3+K2", 2,
     6421, 4102, 78.3, "ESTIMATED", "F2-B"),
    ("F2 parity A=K2 B=K3", "Family 2", "∞", "K2+K3", 2,
     6456, 4165, 77.5, "ESTIMATED", "F2-B 반대 배분"),
    ("F2 parity A=K3 B=K3", "Family 2", "∞", "K3+K3", 2,
     6304, 4050, 77.8, "ESTIMATED", "**Family 2 best**. checkpoint 6개"),
]


def cycles(makespan_iter: float, policy_latency: float) -> float:
    return (
        CYC_PER_ITER * makespan_iter
        + CYC_PER_SHOT * REQUESTS
        + policy_latency * REQUESTS
    )


def main() -> int:
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
    os.makedirs(out_dir, exist_ok=True)

    print("=" * 118)
    print("표 1. 물리 작업과 makespan (단위: Grover 반복). 시뮬레이터가 직접 낸 값")
    print("=" * 118)
    head = (
        f"{'구성':<34}{'family':<10}{'H':>3} {'checkpoint':<8}{'E':>2}"
        f"{'물리작업':>9}{'makespan':>10}{'util':>7}{'vs 정본':>9}  {'등급':<9}"
    )
    print(head)
    print("-" * 118)
    for (name, family, horizon, ckpt, engines, work, span, util, grade, note) in ROWS:
        delta = 100 * (span / BASE_ITER - 1)
        mark = f"{delta:+8.2f}%" if name != "frozen K4/H4 (정본)" else "    기준 "
        print(
            f"{name:<34}{family:<10}{str(horizon):>3} {ckpt:<8}{engines:>2}"
            f"{work:>9,}{span:>10,}{util:>6.1f}%{mark}  {grade:<9}"
        )

    print()
    print("=" * 118)
    print("표 2. 사이클 환산과 policy 지연 민감도 (13절)")
    print("     frozen K4/H4 의 stall 만 계측값입니다. 나머지 열은 전부 ESTIMATED")
    print("=" * 118)
    latencies = (0, 20, 40, 80, 120, 160)
    print(
        f"{'구성':<34}{'E':>2}{'makespan':>9}"
        + "".join(f"{'d=%d' % d:>12}" for d in latencies)
    )
    print("-" * 118)
    base_row = None
    for (name, family, horizon, ckpt, engines, work, span, util, grade, note) in ROWS:
        if family not in ("baseline", "Family 1", "Family 2"):
            continue
        if name == "골든 모델 endpoint-only":
            continue
        values = [cycles(span, d) for d in latencies]
        if name == "frozen K4/H4 (정본)":
            base_row = values
        print(
            f"{name:<34}{engines:>2}{span:>9,}"
            + "".join(f"{v/1e6:>11.2f}M" for v in values)
        )
    print("-" * 118)
    print(
        f"{'frozen K4/H4 실측 (참고)':<34}{1:>2}{BASE_ITER:>9,}"
        f"{'':>12}{'':>12}{'':>12}{'':>12}{'':>12}"
        f"{BASE_CYCLES/1e6:>11.2f}M"
    )
    print(
        f"  실측 stall {BASE_STALL:,} 사이클 = 요청당 {BASE_STALL/REQUESTS:,.0f} 사이클."
    )
    print(
        f"  즉 정본의 실제 노출 지연은 위 표의 d=160 보다 {BASE_STALL/REQUESTS/160:.0f}배 큽니다."
    )

    print()
    print("=" * 118)
    print("표 3. 정본 대비 순위 (makespan 기준)")
    print("=" * 118)
    ranked = sorted(
        [r for r in ROWS if r[1] in ("Family 1", "Family 2", "baseline", "bound")],
        key=lambda r: r[6],
    )
    print(f"{'#':>2} {'구성':<34}{'makespan':>10}{'물리작업':>10}{'vs 정본':>10}  {'비고'}")
    print("-" * 118)
    for index, (name, family, horizon, ckpt, engines, work, span, util, grade, note) in enumerate(ranked, 1):
        delta = 100 * (span / BASE_ITER - 1)
        print(
            f"{index:>2} {name:<34}{span:>10,}{work:>10,}{delta:>+9.2f}%  {note}"
        )

    path = os.path.join(out_dir, "final_comparison.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "configuration", "family", "horizon", "checkpoint", "engines",
                "physical_iterations", "compute_makespan_iter", "engine_utilization_pct",
                "makespan_vs_frozen_pct", "grade", "notes",
            ]
            + [f"est_cycles_d{d}" for d in latencies]
        )
        for (name, family, horizon, ckpt, engines, work, span, util, grade, note) in ROWS:
            writer.writerow(
                [
                    name, family, horizon, ckpt, engines, work, span, util,
                    round(100 * (span / BASE_ITER - 1), 2), grade, note,
                ]
                + [round(cycles(span, d)) for d in latencies]
            )
    print(f"\ncsv {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
