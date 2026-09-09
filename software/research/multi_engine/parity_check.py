#!/usr/bin/env python3
"""
Family 2 파리티 분할의 해석 검산.

시뮬레이터를 짓기 전에 30분 안에 판정하자고 한 그 검산입니다. 지시 7절대로
frozen logical trace 를 전역 인덱스 파리티로 가릅니다.

  Track A : j0, j2, j4, ...
  Track B : j1, j3, j5, ...

두 track 은 서로의 checkpoint 를 절대 못 씁니다 (7절 금지 조항). 그래서 각
track 은 **자기 파리티 부분수열만** 놓고 자기 K 개 슬롯으로 버텨야 합니다.

여기서 재는 것 둘입니다.

1. 물리 작업량. track 별 offline optimum 을 각각 구해 더합니다. offline 이므로
   어떤 online policy 도 이보다 잘할 수 없습니다. 즉 **파리티 분할에 유리한
   최선의 경우**입니다.

2. ideal makespan 하한. max(work_A, work_B) 입니다. 엔진 경합도 없고 ordered
   commit 대기도 없고 투기 폐기도 없다고 본, 물리적으로 도달 불가능한 낙관값입니다.
   지시 11절이 금지한 sum 이 아니라 max 를 씁니다.

두 값 모두 낙관 상한이므로, 여기서 이미 baseline 을 못 이기면 실제 구현은 더
못 이깁니다.

parity 분할이 왜 손해인지도 같이 냅니다. 한 track 이 보는 이웃 요청 간격이
두 배로 벌어지므로 source distance 가 늘어납니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from offline_optimum import offline_optimum  # noqa: E402

BOARD_K4_ONLINE = 4134
OFFLINE_K4 = 4083


def source_distance_stats(requests: list[int], capacity: int) -> list[int]:
    """endpoint-only 최근접 predecessor 를 썼을 때의 source 거리들.

    파리티 분할 전후를 같은 잣대로 비교하려는 것이므로 정책 자체는 단순한 것
    하나로 고정합니다.
    """
    slots: list[int] = []
    distances: list[int] = []
    for request in requests:
        if request in slots:
            distances.append(0)
            continue
        predecessors = [s for s in slots if s < request]
        if predecessors:
            source = max(predecessors)
            distances.append(request - source)
            slots[slots.index(source)] = request
        else:
            distances.append(request)
            if len(slots) < capacity:
                slots.append(request)
            else:
                slots[slots.index(max(slots))] = request
    return distances


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    args = parser.parse_args()

    with open(os.path.join(args.out, "logical_traces.json"), encoding="utf-8") as handle:
        traces = json.load(handle)

    configs = [(2, 2), (3, 2), (2, 3), (3, 3)]
    rows = []
    for trace in traces:
        requests = [int(v) for v in trace["requested_j"]]
        track_a = requests[0::2]
        track_b = requests[1::2]
        row = dict(
            target_count=trace["target_count"],
            seed_index=trace["seed_index"],
            requests=len(requests),
            requests_a=len(track_a),
            requests_b=len(track_b),
            normal=sum(requests),
            single_opt_k4=offline_optimum(requests, 4, "BRIDGE")[0],
        )
        for ka, kb in configs:
            work_a = offline_optimum(track_a, ka, "BRIDGE")[0] if track_a else 0
            work_b = offline_optimum(track_b, kb, "BRIDGE")[0] if track_b else 0
            tag = f"k{ka}{kb}"
            row[f"{tag}_a"] = work_a
            row[f"{tag}_b"] = work_b
            row[f"{tag}_total"] = work_a + work_b
            row[f"{tag}_makespan"] = max(work_a, work_b)
        rows.append(row)

    path = os.path.join(args.out, "parity_check.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    def total(key: str) -> int:
        return sum(r[key] for r in rows)

    print("=== Family 2 파리티 분할, frozen 250 workload, 전부 offline optimum")
    print("    (어떤 online policy 도 이보다 잘할 수 없는 낙관값)\n")
    print(f"{'구성':<16} {'A work':>8} {'B work':>8} {'합계':>8} {'ideal makespan':>15}")
    print(f"{'단일 엔진 K4':<16} {'':>8} {'':>8} {total('single_opt_k4'):>8,} "
          f"{total('single_opt_k4'):>15,}")
    for ka, kb in configs:
        tag = f"k{ka}{kb}"
        print(
            f"{'A=K%d B=K%d' % (ka, kb):<16} {total(tag+'_a'):>8,} {total(tag+'_b'):>8,} "
            f"{total(tag+'_total'):>8,} {total(tag+'_makespan'):>15,}"
        )

    print(f"\n{'구성':<16} {'합계 vs 보드':>13} {'makespan vs 보드':>17} {'판정':>8}")
    for ka, kb in configs:
        tag = f"k{ka}{kb}"
        work_delta = 100 * (total(tag + "_total") / BOARD_K4_ONLINE - 1)
        span_delta = 100 * (total(tag + "_makespan") / BOARD_K4_ONLINE - 1)
        verdict = "이득" if span_delta < 0 else "손해"
        print(
            f"{'A=K%d B=K%d' % (ka, kb):<16} {work_delta:>+12.2f}% "
            f"{span_delta:>+16.2f}% {verdict:>8}"
        )

    # 왜 손해인지 -- source 거리
    single = []
    split = []
    for trace in traces:
        requests = [int(v) for v in trace["requested_j"]]
        single += source_distance_stats(requests, 4)
        split += source_distance_stats(requests[0::2], 2)
        split += source_distance_stats(requests[1::2], 2)
    print("\n=== source 거리 (endpoint-only 최근접, 같은 잣대)")
    print(f"{'':<22} {'평균':>8} {'p50':>6} {'p95':>6} {'최대':>6}")
    for name, data in (("단일 K4", single), ("파리티 분할 K2+K2", split)):
        ordered = sorted(data)
        p95 = ordered[int(0.95 * (len(ordered) - 1))]
        print(
            f"{name:<22} {statistics.mean(data):>8.2f} "
            f"{statistics.median(data):>6.1f} {p95:>6} {max(data):>6}"
        )
    print(f"\nraw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
