#!/usr/bin/env python3
"""
policy work 측정 (연구 지시 12절) 과 후보 탈락 규칙.

## 왜 필요한가

앞서 13절 민감도를 "모든 아키텍처에 같은 결정 지연 d 를 넣어 훑기" 로 했는데
그게 틀렸습니다. **아키텍처마다 policy 복잡도가 다릅니다.** policy 결정이 compute
뒤에 숨지 못하면 연산은 끝났는데 결정을 기다리는 구간이 생기고, 그러면 makespan
이득이 그대로 날아갑니다.

## K4/H4 계측 기준선 (보드 telemetry, MEASURED)

    샷 수                3,647
    결정(solve) 수       3,897   (cold 250 + speculative 3,647)
    policy actions       309,647 -> 결정당 79.46, 샷당 84.90
    policy cycles        1,508,706 -> 결정당 387.15, 샷당 413.68
    action 당 사이클     4.872
    policy stall(노출)   276,027 -> **샷당 75.69**
    은닉률               81.7% (1 - 276,027/1,508,706)

샷당 compute 는 (4,247/3,647) x 1,051.7 = 1,224.7 사이클입니다. policy 413.68 이
평균으로는 그 안에 들어가지만, exact hit 샷(전체의 36%)은 compute 가 0 이라 숨을
곳이 없어 샷당 75.69 가 노출됩니다.

## 탈락 규칙

후보의 결정당 action 이 K4/H4 의 79.46 을 넘으면, 그 후보는 compute 를 줄여
얻은 이득보다 policy 노출이 더 커질 위험이 있습니다. 그런 후보는 makespan 표에서
아무리 좋아 보여도 **버립니다.**

이 스크립트는 DP 를 실제로 돌리며 결정당 action 을 셉니다. RTL 의 action 정의
(끝점 mandatory + 적재 최대 K-1 + 유지, 모두 4개 이내)를 그대로 씁니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import statistics
import sys
from functools import lru_cache
from itertools import combinations

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from online_policy import _next_states  # noqa: E402

# 보드 계측 (MEASURED)
BOARD = dict(
    shots=3647,
    solves=3897,
    actions=309647,
    cycles=1508706,
    stall=276027,
)
BOARD_ACT_PER_SOLVE = BOARD["actions"] / BOARD["solves"]        # 79.46
BOARD_CYC_PER_ACTION = BOARD["cycles"] / BOARD["actions"]       # 4.872
BOARD_STALL_PER_SHOT = BOARD["stall"] / BOARD["shots"]          # 75.69
CYC_PER_ITER = 1051.7


def measure(requests: list[int], capacity: int, horizon: int) -> tuple[int, list[int]]:
    """DP 를 돌리며 결정당 action 수를 셉니다. (총비용, 결정별 action 수)

    action 하나 = "source 를 하나 고르고 그 다음 보유집합 후보를 하나 평가" 입니다.
    RTL 의 Egen/Esort 파이프라인이 세는 단위와 같습니다 -- 끝점은 항상 첫 자리,
    적재는 최대 capacity-1 개, 나머지를 유지로 채우고 4개에서 자릅니다.
    """
    counts: list[int] = []

    @lru_cache(maxsize=1 << 20)
    def window(held: tuple[int, ...], win: tuple[int, ...]) -> tuple[int, int]:
        if not win:
            return (0, 0)
        request = win[0]
        rest = win[1:]
        best = (1 << 30, 1 << 30)
        for source in sorted({0, *[p for p in held if p <= request]}, reverse=True):
            cost = request - source
            for state in _next_states(capacity, held, source, request, rest):
                tail = window(state, rest)
                cand = (cost + tail[0], int(cost > 0) + tail[1])
                if cand < best:
                    best = cand
            if best[0] == 0:
                break
        return best

    held: tuple[int, ...] = ()
    total = 0
    for index, request in enumerate(requests):
        win = tuple(requests[index + 1 : index + 1 + horizon])
        actions = 0
        best = (1 << 30, 1 << 30)
        pick_source, pick_state = 0, held
        for source in sorted({0, *[p for p in held if p <= request]}, reverse=True):
            cost = request - source
            for state in _next_states(capacity, held, source, request, win):
                actions += 1
                tail = window(state, win)
                cand = (cost + tail[0], int(cost > 0) + tail[1])
                if cand < best:
                    best, pick_source, pick_state = cand, source, state
        counts.append(actions)
        total += request - pick_source
        held = pick_state
    return total, counts


def stats(values: list[int]) -> dict:
    ordered = sorted(values)
    return dict(
        decisions=len(values),
        actions=sum(values),
        mean=sum(values) / len(values),
        p50=statistics.median(values),
        p95=ordered[int(0.95 * (len(ordered) - 1))],
        max=max(values),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    args = parser.parse_args()

    with open(os.path.join(args.out, "logical_traces.json"), encoding="utf-8") as handle:
        traces = json.load(handle)
    all_requests = [[int(v) for v in t["requested_j"]] for t in traces]

    # 검사할 구성. Family 2 는 track 별로 자기 K 와 자기 DP 를 돌립니다.
    configs = [
        ("K4/H4 (기준선)", 4, 4, "single"),
        ("K4/H2", 4, 2, "single"),
        ("K4/H3", 4, 3, "single"),
        ("K4/H5", 4, 5, "single"),
        ("K4/H6", 4, 6, "single"),
        ("K3/H4", 3, 4, "single"),
        ("K5/H4", 5, 4, "single"),
        ("K6/H4", 6, 4, "single"),
        ("F1 C3 (shared pool)", 3, 4, "single"),
        ("F1 C5 (shared pool)", 5, 4, "single"),
        ("F2 track A=K2", 2, 4, "even"),
        ("F2 track B=K2", 2, 4, "odd"),
        ("F2 track A=K3", 3, 4, "even"),
        ("F2 track B=K3", 3, 4, "odd"),
    ]

    rows = []
    for name, capacity, horizon, split in configs:
        counts: list[int] = []
        work = 0
        for requests in all_requests:
            seq = (
                requests
                if split == "single"
                else requests[0::2] if split == "even" else requests[1::2]
            )
            if not seq:
                continue
            cost, per = measure(seq, capacity, horizon)
            work += cost
            counts += per
        s = stats(counts)
        s.update(name=name, K=capacity, H=horizon, work=work)
        rows.append(s)

    # 기준선의 결정당 action 을 보드 계측 79.46 에 맞추는 배율.
    base = next(r for r in rows if r["name"] == "K4/H4 (기준선)")
    scale = BOARD_ACT_PER_SOLVE / base["mean"]

    print("=== policy work (지시 12절). DP 를 실제로 돌려 센 값")
    print(f"  기준선 결정당 action  모델 {base['mean']:.2f}  보드 계측 {BOARD_ACT_PER_SOLVE:.2f}"
          f"   -> 보정 배율 {scale:.3f}")
    print(f"  action 당 사이클 {BOARD_CYC_PER_ACTION:.3f} (보드 계측)")
    print()
    print(f"{'구성':<22}{'K':>2}{'H':>3}{'결정':>7}{'action':>9}{'결정당':>8}"
          f"{'p95':>6}{'최대':>6}{'보정 사이클/결정':>16}{'vs 기준선':>10}")
    print("-" * 100)
    for r in rows:
        cyc = r["mean"] * scale * BOARD_CYC_PER_ACTION
        ratio = r["mean"] / base["mean"]
        mark = "" if r["name"] == "K4/H4 (기준선)" else ("  탈락" if ratio > 1.0 else "  통과")
        print(
            f"{r['name']:<22}{r['K']:>2}{r['H']:>3}{r['decisions']:>7,}{r['actions']:>9,}"
            f"{r['mean']:>8.2f}{r['p95']:>6}{r['max']:>6}{cyc:>15.1f}"
            f"{ratio:>9.2f}x{mark}"
        )

    path = os.path.join(args.out, "policy_work.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["name", "K", "H", "decisions", "actions", "mean", "p50", "p95", "max", "work"],
        )
        writer.writeheader()
        for r in rows:
            writer.writerow({k: r[k] for k in writer.fieldnames})
    print(f"\nraw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
