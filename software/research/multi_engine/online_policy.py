#!/usr/bin/env python3
"""
restricted-B rolling policy 의 SW 재현 (연구 지시 8절 (2) 단계).

골든 모델의 `V098CheckpointReference` 는 endpoint-only 라 보드 실측보다 41.5%
더 일합니다. 실물 RTL 이 하는 일은 `grover_checkpoint.v` 머리말에 적혀 있습니다.

    4) grover_ckpt_planner
       - logical {source_j, sorted S'} -> deterministic physical slot plan
       - closest predecessor, endpoint mandatory, exact hit, psi0 anchor
       - K3 max 2 / K4 max 3 B-mode intermediates
    5) grover_ckpt_executor
       - INIT, in-place run, 1-iteration out-of-place bridge

여기서 옮기는 것은 그 중 **논리 부분만**입니다. 물리 슬롯 번호, BRAM 포트,
사이클은 17절대로 건드리지 않습니다. 옮긴 규칙은 셋입니다.

1. source 는 보유 집합 ∪ {ψ0} 중 요청 이하인 것에서 고릅니다
2. 한 번 전진하는 동안 지나간 위치 중 최대 K-1 개를 **추가 Grover 반복 없이**
   중간 checkpoint 로 떨어뜨릴 수 있고, 끝점은 반드시 남깁니다 (endpoint
   mandatory). 첫 반복이 out-of-place bridge 라 source 도 파괴되지 않습니다
3. 어느 조합을 고를지는 미래 H 개 요청을 내다보는 정확한 DP 로 정합니다.
   receding horizon 이라 이번 한 걸음만 확정하고 다음 요청에서 다시 풉니다

미래 요청값은 RTL 의 Shadow-J 가 J LFSR 을 미리 돌려 얻는 것과 같습니다.
frozen trace 에서 250/250 모두 마지막 trial 에서만 성공하므로, 실패를 가정하고
앞서 뽑는 Shadow-J 예측은 마지막 직전까지 정확합니다. 그래서 trace 의 다음 H 개를
그대로 씁니다 -- illegal future knowledge 가 아니라 RTL 이 실제로 아는 값입니다.

동점 처리는 골든 모델 `_rolling_score` 와 같게 (총비용, 구간수) 사전식입니다.
구간수는 비용이 0 이 아닌 걸음의 개수입니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from functools import lru_cache
from itertools import combinations

INF = float("inf")


def _deposit_options(
    capacity: int, source: int, request: int, future: tuple[int, ...]
) -> list[tuple[int, ...]]:
    """이번 전진에서 남길 수 있는 위치 조합. 끝점은 항상 포함합니다."""
    inpath = sorted({v for v in future if source <= v < request})
    options: list[tuple[int, ...]] = [(request,)]
    for size in range(1, capacity):
        if size > len(inpath):
            break
        for chosen in combinations(inpath, size):
            options.append(tuple(sorted((*chosen, request))))
    return options


def _next_states(
    capacity: int, held: tuple[int, ...], source: int, request: int,
    future: tuple[int, ...],
) -> list[tuple[int, ...]]:
    out: list[tuple[int, ...]] = []
    for deposit in _deposit_options(capacity, source, request, future):
        keep_pool = tuple(p for p in held if p not in deposit and p > 0)
        room = capacity - len(deposit)
        if room <= 0:
            out.append(tuple(sorted(deposit)))
            continue
        if len(keep_pool) <= room:
            out.append(tuple(sorted((*keep_pool, *deposit))))
        else:
            for keep in combinations(keep_pool, room):
                out.append(tuple(sorted((*keep, *deposit))))
    # 중복 제거 (같은 집합이 여러 조합에서 나옵니다)
    return sorted(set(out))


def make_scorer(capacity: int):
    @lru_cache(maxsize=1 << 20)
    def window_cost(held: tuple[int, ...], window: tuple[int, ...]) -> tuple[int, int]:
        """창 안의 요청들을 최소 비용으로 처리했을 때 (총비용, 구간수)."""
        if not window:
            return (0, 0)
        request = window[0]
        rest = window[1:]
        best = (INF, INF)
        for source in sorted({0, *[p for p in held if p <= request]}, reverse=True):
            cost = request - source
            for state in _next_states(capacity, held, source, request, rest):
                tail_cost, tail_segments = window_cost(state, rest)
                candidate = (cost + tail_cost, int(cost > 0) + tail_segments)
                if candidate < best:
                    best = candidate
            if best[0] == 0:
                break
        return best

    return window_cost


def run_policy(
    requests: list[int], capacity: int, horizon: int, scorer
) -> tuple[int, list[dict]]:
    """receding-horizon 으로 한 걸음씩 확정합니다."""
    held: tuple[int, ...] = ()
    total = 0
    trace: list[dict] = []
    for index, request in enumerate(requests):
        window = tuple(requests[index + 1 : index + 1 + horizon])
        before = held
        best = (INF, INF)
        chosen_source = 0
        chosen_state = held
        for source in sorted({0, *[p for p in held if p <= request]}, reverse=True):
            cost = request - source
            for state in _next_states(capacity, held, source, request, window):
                tail_cost, tail_segments = scorer(state, window)
                candidate = (cost + tail_cost, int(cost > 0) + tail_segments)
                if candidate < best:
                    best = candidate
                    chosen_source = source
                    chosen_state = state
            if best[0] == request - max(
                sorted({0, *[p for p in held if p <= request]})
            ) and best[0] == 0:
                break
        cost = request - chosen_source
        total += cost
        trace.append(
            dict(
                index=index,
                requested_j=request,
                before=list(before),
                source=chosen_source,
                physical=cost,
                after=list(chosen_state),
            )
        )
        held = chosen_state
    return total, trace


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument("--capacity", type=int, default=4)
    parser.add_argument("--horizons", default="1,2,3,4,5,6,8")
    parser.add_argument("--trace-samples", type=int, default=3)
    args = parser.parse_args()

    with open(os.path.join(args.out, "logical_traces.json"), encoding="utf-8") as handle:
        traces = json.load(handle)
    horizons = [int(h) for h in args.horizons.split(",")]

    board = {1: 2230, 4: 1007, 16: 532, 64: 234, 256: 131}
    rows = []
    samples: list[dict] = []
    for horizon in horizons:
        scorer = make_scorer(args.capacity)
        per_target = {m: 0 for m in board}
        for trace in traces:
            requests = [int(v) for v in trace["requested_j"]]
            cost, steps = run_policy(requests, args.capacity, horizon, scorer)
            per_target[trace["target_count"]] += cost
            if (
                horizon == 4
                and trace["seed_index"] < args.trace_samples
                and trace["target_count"] == 1
            ):
                samples.append(
                    dict(
                        target_count=trace["target_count"],
                        seed_index=trace["seed_index"],
                        total=cost,
                        steps=steps,
                    )
                )
        row = dict(horizon=horizon, total=sum(per_target.values()))
        row.update({f"m{m}": per_target[m] for m in board})
        rows.append(row)

    path = os.path.join(args.out, f"online_policy_k{args.capacity}.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    with open(os.path.join(args.out, "online_policy_traces.json"), "w", encoding="utf-8") as handle:
        json.dump(samples, handle, indent=1)

    board_total = sum(board.values())
    print(f"=== restricted-B online policy, K={args.capacity}, frozen 250 workload")
    print(f"{'H':>3} {'total':>8} {'보드 4,134 대비':>15} " + " ".join(
        f"{'M=%d' % m:>7}" for m in board))
    for row in rows:
        delta = 100 * (row["total"] / board_total - 1)
        cells = " ".join(f"{row['m%d' % m]:>7,}" for m in board)
        mark = "  <-- 일치" if row["total"] == board_total else ""
        print(f"{row['horizon']:>3} {row['total']:>8,} {delta:>+14.2f}% {cells}{mark}")
    print(f"\n보드 M별 정본  " + " ".join(f"{board[m]:>7,}" for m in board))
    print(f"raw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
