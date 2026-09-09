#!/usr/bin/env python3
"""
policy stall 분석 -- 남은 레버가 어디인지.

11절에서 물리 반복이 offline 최적의 1.23% 안쪽이고, 12·13절에서 병렬화가 2%
안쪽임을 봤습니다. 그러면 사이클은 어디로 가고 있는가를 봅니다.

2026-09-01 보드 실측(`summary.csv`)에는 조건별로 다음이 남아 있습니다.

    normal_iter, normal_cycles      checkpoint 를 끈 실행
    k4_iter, k4_cycles              checkpoint 를 켠 실행
    k4_policy_stall                 그 중 policy 결정을 기다린 사이클

Normal 실행에는 policy 가 없으므로, Normal 에서 "반복당 사이클" 과 "샷당
고정비" 를 뽑아내면 K4 의 사이클 예산을 셋으로 가를 수 있습니다.

    compute   물리 반복에 실제로 쓴 사이클
    stall     policy 결정을 기다린 사이클 (계측값)
    나머지    적재·측정·검증 등 그 밖의 고정비

MEASURED / ESTIMATED 구분 (13절):
  - normal_*, k4_*, k4_policy_stall 은 전부 MEASURED
  - "반복당 사이클" 회귀와 stall 을 없앴을 때의 사이클은 ESTIMATED
"""
from __future__ import annotations

import json
import os
import sys

# 보드 실측. summary.csv 그대로입니다 (MEASURED).
BOARD = {
    1: dict(n_iter=8414, n_cyc=10186883, k_iter=2230, k_cyc=6443381, k_stall=3186294),
    4: dict(n_iter=3615, n_cyc=4940549, k_iter=1007, k_cyc=3717106, k_stall=1902711),
    16: dict(n_iter=1882, n_cyc=2920180, k_iter=532, k_cyc=2099548, k_stall=919654),
    64: dict(n_iter=662, n_cyc=1359349, k_iter=234, k_cyc=1015193, k_stall=329292),
    256: dict(n_iter=310, n_cyc=822794, k_iter=131, k_cyc=549578, k_stall=78417),
}
TARGETS = (1, 4, 16, 64, 256)


def main() -> int:
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
    with open(os.path.join(out_dir, "logical_traces.json"), encoding="utf-8") as handle:
        traces = json.load(handle)
    trials = {m: 0 for m in TARGETS}
    for trace in traces:
        trials[trace["target_count"]] += trace["trial_count"]

    # Normal 에서 (반복당 사이클 a, 샷당 고정비 b) 를 최소제곱으로 뽑습니다.
    # cycles = a * iter + b * trial. policy 가 없는 실행이므로 순수 실행 비용입니다.
    sxx = sxy = sxz = syy = syz = 0.0
    for m in TARGETS:
        x = BOARD[m]["n_iter"]
        y = trials[m]
        z = BOARD[m]["n_cyc"]
        sxx += x * x
        sxy += x * y
        syy += y * y
        sxz += x * z
        syz += y * z
    det = sxx * syy - sxy * sxy
    a = (sxz * syy - syz * sxy) / det
    b = (syz * sxx - sxz * sxy) / det

    print("=== Normal 실행에서 뽑은 실행 비용 (ESTIMATED, 최소제곱)")
    print(f"  반복당 사이클 a = {a:,.1f}")
    print(f"  샷당 고정비   b = {b:,.1f}")
    print(f"{'M':>4} {'실측 Normal':>12} {'모델':>12} {'오차':>7}")
    for m in TARGETS:
        model = a * BOARD[m]["n_iter"] + b * trials[m]
        err = 100 * (model / BOARD[m]["n_cyc"] - 1)
        print(f"{m:>4} {BOARD[m]['n_cyc']:>12,} {model:>12,.0f} {err:>+6.2f}%")

    print("\n=== 모델 없이 바로 나오는 것 (전부 MEASURED)")
    k4_total_m = sum(BOARD[m]["k_cyc"] for m in TARGETS)
    stall_total_m = sum(BOARD[m]["k_stall"] for m in TARGETS)
    print(f"{'M':>4} {'K4 사이클':>11} {'policy stall':>13} {'비중':>7}")
    for m in TARGETS:
        print(
            f"{m:>4} {BOARD[m]['k_cyc']:>11,} {BOARD[m]['k_stall']:>13,} "
            f"{100*BOARD[m]['k_stall']/BOARD[m]['k_cyc']:>6.1f}%"
        )
    print(
        f"{'합계':>4} {k4_total_m:>11,} {stall_total_m:>13,} "
        f"{100*stall_total_m/k4_total_m:>6.1f}%"
    )

    print("\n=== K4 사이클 예산 가르기 (compute 는 ESTIMATED)")
    print(
        f"{'M':>4} {'K4 사이클':>11} {'compute':>10} {'stall':>10} {'stall 비중':>10} "
        f"{'나머지':>10}"
    )
    tot = dict(cyc=0, comp=0, stall=0, rest=0)
    for m in TARGETS:
        cyc = BOARD[m]["k_cyc"]
        comp = a * BOARD[m]["k_iter"] + b * trials[m]
        stall = BOARD[m]["k_stall"]
        rest = cyc - comp - stall
        tot["cyc"] += cyc
        tot["comp"] += comp
        tot["stall"] += stall
        tot["rest"] += rest
        print(
            f"{m:>4} {cyc:>11,} {comp:>10,.0f} {stall:>10,} "
            f"{100*stall/cyc:>9.1f}% {rest:>10,.0f}"
        )
    print(
        f"{'합계':>4} {tot['cyc']:>11,} {tot['comp']:>10,.0f} {tot['stall']:>10,} "
        f"{100*tot['stall']/tot['cyc']:>9.1f}% {tot['rest']:>10,.0f}"
    )
    print(
        "\n  '나머지' 가 음수인 것은 모델의 한계입니다. Normal 에서 뽑은 샷당\n"
        "  고정비 b 를 K4 에 그대로 쓴 탓입니다 -- K4 는 exact hit 샷이 36% 라\n"
        "  그 샷들이 INIT·전진 경로를 통째로 건너뛰어 실제 고정비가 더 쌉니다.\n"
        "  따라서 위 compute 열은 **상한**으로 읽으십시오. stall 비중 46.4% 는\n"
        "  측정값 두 개의 비라 모델과 무관하게 정확합니다."
    )

    print("\n=== stall 을 없앴을 때 (ESTIMATED)")
    normal_total = sum(BOARD[m]["n_cyc"] for m in TARGETS)
    k4_total = sum(BOARD[m]["k_cyc"] for m in TARGETS)
    no_stall = k4_total - tot["stall"]
    print(f"  Normal 실측                 {normal_total:>12,}")
    print(f"  K4 실측                     {k4_total:>12,}  ({100*(1-k4_total/normal_total):>5.2f}% 단축)")
    print(f"  K4, stall = 0               {no_stall:>12,}  ({100*(1-no_stall/normal_total):>5.2f}% 단축)")

    # 물리 반복 쪽 남은 여지 (11절) 를 사이클로 환산해 비교합니다.
    offline_gain_iter = 4134 - 4083
    offline_gain_cycles = a * offline_gain_iter
    print("\n=== 두 레버의 크기 비교 (같은 잣대: 사이클)")
    print(f"  물리 반복을 offline 최적까지 (4,134 -> 4,083)  {offline_gain_cycles:>12,.0f}")
    print(f"  policy stall 을 0 으로                          {tot['stall']:>12,}")
    print(f"  배수                                            {tot['stall']/offline_gain_cycles:>12,.0f}배")

    print("\n=== 엔진 2벌이 stall 을 못 건드리는 이유")
    print("  Family 1/2 는 compute 를 나눠 갖습니다. stall 은 policy 결정 지연이라")
    print("  엔진을 늘려도 그대로 남고, 오히려 결정 횟수가 늘어 커집니다.")
    span = tot["comp"] / 2 + tot["stall"] + tot["rest"]
    print(f"  compute 를 완벽히 반으로 갈랐다고 쳐도 (도달 불가): {span:>12,.0f}")
    print(f"  = 실측 K4 대비 {100*(1-span/k4_total):>5.2f}% 단축이 상한")
    return 0


if __name__ == "__main__":
    sys.exit(main())
