#!/usr/bin/env python3
"""
frozen 250 workload 의 checkpoint offline optimum.

**아키텍처를 만들기 전에 천장을 먼저 재는 단계입니다.** 요청 j 시퀀스는 frozen
trace 라 사후에 전부 알고 있으므로, 어떤 online policy 도 넘을 수 없는 하한을
정확히 구할 수 있습니다. 이 값이 보드 실측 4,134 와 얼마나 떨어져 있느냐가
Family 1 / Family 2 가 가져갈 수 있는 최대치입니다.

## 문제의 구조

ψ0 을 0 번 위치로 두면 이것은 **직선 위의 forward-only 캐시** 문제입니다.

  - 위치 0 (ψ0) 은 언제나 공짜이고 슬롯을 차지하지 않습니다 (지시 1절)
  - 슬롯 K 개가 각각 어떤 위치 하나를 담습니다
  - 요청 j 를 처리하려면 j 이하인 보유 위치 c 를 골라 j 까지 전진합니다.
    비용은 Grover 반복 j - c 입니다
  - 전진하면서 지나간 위치들은 그 순간 실제로 존재합니다

마지막 줄이 핵심입니다. 실물 RTL 은 이걸 이미 씁니다 -- grover_ckpt_planner 의
"K4 max 3 B-mode intermediates" 와 grover_ckpt_executor 의 1-iteration
out-of-place bridge 가 (i) source 를 파괴하지 않고 (ii) 지나가는 길에 중간
checkpoint 를 추가 반복 없이 떨어뜨리는 장치입니다.

## 네 가지 비용 모델

  NORMAL      checkpoint 없음. 매번 ψ0 에서. 비용 = sum(j)
  ENDPOINT    online, endpoint-only, destructive.
              골든 모델 V098CheckpointReference 와 같은 규칙.
              trace 추출이 맞는지 검산하는 용도입니다
  OPT-E       offline 최적, endpoint-only, destructive
  OPT-P       offline 최적, source 보존(non-destructive), 중간 적재 없음
  OPT-B       offline 최적, source 보존 + 경로 중간 적재 최대 K-1
              실물 RTL 이 속한 능력 계급의 하한

OPT-B 가 이 아키텍처 계급의 진짜 천장입니다.

## 왜 후보 위치를 미래 요청으로 제한해도 되는가

위치 p 를 들고 있어 이득을 보는 것은 p 이상인 미래 요청 j' 뿐이고, 그 이득은
j' - p 입니다. 구간 [c, j] 안에서 j' 에 가장 좋은 위치는 min(j', j) 입니다.
따라서 적재 후보를 "[c, j] 안에 있는 미래 요청값" 으로 좁혀도 최적해를 놓치지
않습니다. 이걸로 상태공간이 workload 당 수천 개로 줄어 정확히 풀립니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from functools import lru_cache
from itertools import combinations

K_DEFAULT = 4


# ---------------------------------------------------------------------------
# online 재생 (검산용)
# ---------------------------------------------------------------------------
def replay_endpoint_online(requests: list[int], capacity: int) -> int:
    """골든 모델과 같은 endpoint-only destructive 규칙을 그대로 재생합니다.

    - 정확히 일치하는 슬롯이 있으면 비용 0, 상태 그대로
    - j 미만인 슬롯이 있으면 가장 가까운 것을 골라 전진 (그 슬롯이 j 가 됨)
    - 없으면 ψ0 에서 비용 j. 빈 슬롯이 있으면 채우고, 없으면 하나를 버림
      (버리는 대상은 골든 모델이 rolling score 로 고르지만, 이 갈래는 전체의
       0.16% 라 총합에 영향이 없습니다. 여기서는 가장 큰 것을 버립니다)
    """
    slots: list[int] = []
    total = 0
    for request in requests:
        if request in slots:
            continue
        predecessors = [s for s in slots if s < request]
        if predecessors:
            source = max(predecessors)
            total += request - source
            slots[slots.index(source)] = request
            continue
        total += request
        if len(slots) < capacity:
            slots.append(request)
        else:
            slots[slots.index(max(slots))] = request
    return total


# ---------------------------------------------------------------------------
# offline 최적
# ---------------------------------------------------------------------------

def _successors(
    mode: str,
    capacity: int,
    useful: tuple[int, ...],
    source: int,
    request: int,
    future: tuple[int, ...],
) -> list[tuple[int, ...]]:
    """요청 하나를 source 에서 처리한 뒤 가능한 보유 집합들."""
    if mode == "ENDPOINT":
        if request in useful:
            return [useful]
        if source in useful:
            rest = tuple(p for p in useful if p != source)
            return [tuple(sorted((*rest, request)))]
        if len(useful) < capacity:
            return [tuple(sorted((*useful, request)))]
        return [
            tuple(sorted((*[p for p in useful if p != victim], request)))
            for victim in useful
        ]

    if mode == "PRESERVE":
        deposits = [(request,)]
    else:  # BRIDGE -- 지나간 길에 최대 capacity-1 개를 추가 반복 없이 적재
        inpath = [value for value in future if source <= value < request]
        deposits = [(request,)]
        for size in range(1, capacity):
            if size > len(inpath):
                break
            for chosen in combinations(inpath, size):
                deposits.append(tuple(sorted((*chosen, request))))

    out: list[tuple[int, ...]] = []
    for deposit in deposits:
        keep_pool = tuple(p for p in useful if p not in deposit)
        room = capacity - len(deposit)
        if room <= 0:
            out.append(tuple(sorted(deposit)))
            continue
        if len(keep_pool) <= room:
            out.append(tuple(sorted((*keep_pool, *deposit))))
        else:
            for keep in combinations(keep_pool, room):
                out.append(tuple(sorted((*keep, *deposit))))
    return out


def offline_optimum(
    requests: list[int], capacity: int, mode: str
) -> tuple[int, list[int]]:
    """mode in {"ENDPOINT", "PRESERVE", "BRIDGE"} 의 정확한 offline 최소 비용."""
    total_steps = len(requests)
    # step t 이후에 나오는 서로 다른 요청값. 후보 위치를 여기로 제한합니다.
    future_values: list[tuple[int, ...]] = [()] * (total_steps + 1)
    seen: set[int] = set()
    for index in range(total_steps - 1, -1, -1):
        future_values[index] = tuple(sorted(seen))
        seen.add(requests[index])
    max_future = [0] * (total_steps + 1)
    for index in range(total_steps - 1, -1, -1):
        max_future[index] = max(requests[index], max_future[index + 1])

    @lru_cache(maxsize=None)
    def solve(step: int, held: tuple[int, ...]) -> int:
        if step == total_steps:
            return 0
        request = requests[step]
        # 이 시점 이후 아무 요청도 도달하지 못하는 위치는 들고 있어도 무의미합니다.
        useful = tuple(p for p in held if p <= max_future[step])
        sources = sorted({0, *[p for p in useful if p <= request]}, reverse=True)
        best = None

        for source in sources:
            cost = request - source
            candidates = _successors(
                mode, capacity, useful, source, request, future_values[step]
            )
            for candidate in candidates:
                value = cost + solve(step + 1, candidate)
                if best is None or value < best:
                    best = value
            if best is not None and best == cost and source == max(sources):
                break  # 비용 0 (exact hit) 보다 나은 것은 없습니다
        return 0 if best is None else best

    result = solve(0, ())

    # 최적 경로를 되짚어 요청별 비용 열을 복원합니다. dual-engine 스케줄링
    # 상한을 내려면 총합이 아니라 job 하나하나의 크기가 필요합니다.
    costs: list[int] = []
    held: tuple[int, ...] = ()
    for step in range(total_steps):
        target = solve(step, held)
        chosen = None
        request = requests[step]
        useful = tuple(p for p in held if p <= max_future[step])
        for source in sorted({0, *[p for p in useful if p <= request]}, reverse=True):
            cost = request - source
            for candidate in _successors(
                mode, capacity, useful, source, request, future_values[step]
            ):
                if cost + solve(step + 1, candidate) == target:
                    chosen = (cost, candidate)
                    break
            if chosen:
                break
        if chosen is None:  # 도달 불가. 논리적으로 생길 수 없습니다.
            raise RuntimeError("optimal path reconstruction failed")
        costs.append(chosen[0])
        held = chosen[1]
    solve.cache_clear()
    return result, costs


# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument("--capacity", type=int, default=K_DEFAULT)
    parser.add_argument("--modes", default="ENDPOINT,PRESERVE,BRIDGE")
    args = parser.parse_args()

    with open(os.path.join(args.out, "logical_traces.json"), encoding="utf-8") as handle:
        traces = json.load(handle)
    modes = [m.strip() for m in args.modes.split(",") if m.strip()]

    rows = []
    for trace in traces:
        requests = [int(v) for v in trace["requested_j"]]
        row = dict(
            target_count=trace["target_count"],
            seed_index=trace["seed_index"],
            requests=len(requests),
            normal=sum(requests),
            golden_online=trace["golden_ckpt_physical"],
            replay_online=replay_endpoint_online(requests, args.capacity),
        )
        for mode in modes:
            row[f"opt_{mode.lower()}"] = offline_optimum(
                requests, args.capacity, mode
            )[0]
        rows.append(row)

    path = os.path.join(args.out, f"offline_optimum_k{args.capacity}.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    def total(key: str) -> int:
        return sum(r[key] for r in rows)

    board_k4 = 4134
    print(f"=== offline optimum, K={args.capacity}, frozen 250 workload")
    print(f"{'모델':<28} {'물리 반복':>10} {'Normal 대비':>11} {'보드 K4 대비':>12}")
    entries = [
        ("NORMAL (checkpoint 없음)", total("normal")),
        ("골든 online (endpoint)", total("golden_online")),
        ("재생 online (검산)", total("replay_online")),
    ]
    entries += [(f"OFFLINE OPT {m}", total(f"opt_{m.lower()}")) for m in modes]
    entries.append(("보드 실측 K4 (online, B-mode)", board_k4))
    base = total("normal")
    for name, value in entries:
        print(
            f"{name:<28} {value:>10,} {100*(1-value/base):>10.2f}% "
            f"{100*(value/board_k4-1):>+11.2f}%"
        )
    print(f"\nraw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
