#!/usr/bin/env python3
"""
Family 1 (shared C3/R2, 엔진 2벌) 의 낙관적 makespan 상한.

시뮬레이터를 짓기 전에 "최선의 경우에도 얼마나 벌 수 있나" 를 먼저 봅니다.
여기서 나오는 값은 **도달 불가능한 낙관값**입니다. 실제 구현은 반드시 이보다
나쁩니다. 그러니 이 값이 baseline 을 못 이기면 설계를 접는 근거가 됩니다.

## 낙관적으로 잡은 것 (전부 Family 1 에 유리한 쪽)

1. job 비용을 **순차 offline optimum** 의 비용 열로 씁니다. 실제로는 job t 와
   t+1 이 동시에 돌면 t 가 만든 checkpoint 를 t+1 이 못 씁니다. 즉 실제 비용은
   더 큽니다.
2. checkpoint 적재·복사·bridge 오버헤드 0.
3. 엔진과 메모리 포트 경합 0. BRAM 포트 충돌은 17절대로 모델링하지 않습니다.
4. policy 결정 지연 0.
5. ordered commit 대기 0 (자기 차례를 기다리는 stall 없음).
6. 마지막 성공 trial 옆에서 같이 돌던 투기 job 의 낭비를 세지 않습니다.

## 검사한 checkpoint 예산 두 가지

  C3   지시 2절 그대로. 재사용 checkpoint 3개 (R0/R1 은 목적지 슬롯)
  C5   가장 관대한 해석. 다섯 상태 전부를 재사용 checkpoint 로 칠 수 있다고 봄

## 스케줄

논리 순서대로 job 을 내고, 매번 먼저 비는 엔진에 붙입니다 (work-conserving,
F1-2 의 async refill 에 해당). 동시에 최대 2개까지만 in flight 입니다 (R2).
makespan 은 마지막 job 이 끝나는 시각입니다.

하한도 같이 냅니다. 어떤 스케줄도 max(총작업/E, 최대 job) 보다 짧을 수 없습니다.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from offline_optimum import offline_optimum  # noqa: E402

BOARD_K4_ONLINE = 4134


def list_schedule(costs: list[int], engines: int) -> int:
    """논리 순서대로 내되 먼저 비는 엔진에 붙이는 스케줄의 makespan."""
    available = [0] * engines
    finish = 0
    for cost in costs:
        index = min(range(engines), key=lambda i: available[i])
        start = available[index]
        available[index] = start + cost
        finish = max(finish, available[index])
    return finish


def _schedule(
    requests: list[int],
    capacity: int,
    engines: int,
    in_flight_cap: int,
    gated: bool,
) -> tuple[int, int, int, int]:
    """가시성 제약을 지키는 event-driven 스케줄. (makespan, 작업, 유휴, 대기결정)

    앞의 list_schedule 은 job 비용을 **순차** offline optimum 에서 가져옵니다.
    그건 job t 와 t+1 이 동시에 도는데도 t 가 만든 checkpoint 를 t+1 이 쓴다고
    친 것이라 낙관이 지나칩니다. 여기서는 그 낙관을 걷어냅니다.

      - job 은 **낼 때** 보이는 checkpoint 집합만 씁니다
      - job 이 끝나야 그 결과(끝점 + 경로 중간 적재)가 집합에 들어갑니다
      - 슬롯이 모자라면 다음 재사용이 가장 먼 것을 버립니다 (Belady)
      - 동시에 최대 in_flight_cap 개 (Family 1 의 R2)
      - pair barrier 없음. 엔진이 비고 낼 job 이 있으면 바로 냅니다

    gated=False   빈 엔진이 있으면 무조건 냅니다 (F1-2 의 work-conserving refill)
    gated=True    두 시각을 견줘 이른 쪽을 고릅니다
                    지금 낸다 : t + cost(보이는 집합)
                    기다린다  : 앞 job 이 끝나는 시각 + cost(그 끝점을 더한 집합)
                  앞 job 의 끝점은 이미 발행된 값이므로 미래 지식이 아닙니다.

    적재·퇴출은 미래 요청을 보고 고르므로 **정책 쪽은 두 변형 모두 낙관적**입니다.
    """
    total_steps = len(requests)
    held: list[int] = []
    inflight: list[tuple[int, int, int]] = []  # (끝나는 시각, source, step)
    now = 0
    work = 0
    idle = 0
    waits = 0
    step = 0

    def cost_from(request: int, pool: list[int]) -> tuple[int, int]:
        predecessors = [p for p in pool if p <= request]
        source = max(predecessors) if predecessors else 0
        return request - source, source

    def marginal_value(position: int, pool: list[int], from_step: int) -> int:
        """이 위치를 버리면 다음 사용 때 얼마나 손해인가.

        직선 위에서 j 를 p 에서 처리하면 비용이 j-p 이고 ψ0 에서 하면 j 입니다.
        따라서 p 를 들고 있어 버는 것은 "p 를 쓸 다음 요청" 하나에서
        p - (그 요청에게 차선인 source) 만큼입니다. 차선이 ψ0 이면 그냥 p 입니다.

        단순 LRU/Belady 로 "다음에 도달 가능한 시점" 만 보면 안 됩니다. 위치 0
        근처의 작은 checkpoint 는 거의 매 요청이 도달할 수 있어 next-use 가
        항상 가깝지만, ψ0 가 공짜라 값어치는 0 입니다. 그 함정 때문에 큰
        checkpoint 가 슬롯에 못 들어가는 일이 생깁니다.
        """
        others = [q for q in pool if q != position]
        for index in range(from_step, total_steps):
            request = requests[index]
            if request < position:
                continue
            best_other = max([q for q in others if q <= request], default=0)
            if best_other >= position:
                return 0  # 더 좋거나 같은 대체가 이미 있습니다
            return position - best_other
        return 0  # 다시 쓰일 일이 없습니다

    def retire(source: int, done_step: int) -> None:
        request = requests[done_step]
        deposits = [request]
        for value in sorted(
            {v for v in requests[done_step + 1 :] if source <= v < request},
            reverse=True,
        ):
            if len(deposits) >= capacity:
                break
            deposits.append(value)
        for value in deposits:
            # ψ0 은 언제나 공짜입니다. 슬롯을 쓰면 안 됩니다 (지시 1절).
            if value <= 0 or value in held:
                continue
            if len(held) < capacity:
                held.append(value)
                continue
            victim = min(held, key=lambda p: marginal_value(p, held, done_step + 1))
            incoming = marginal_value(value, held + [value], done_step + 1)
            if marginal_value(victim, held, done_step + 1) < incoming:
                held[held.index(victim)] = value

    while step < total_steps or inflight:
        busy = len(inflight)
        can_issue = (
            step < total_steps and busy < engines and busy < in_flight_cap
        )
        if can_issue:
            request = requests[step]
            cost_now, source_now = cost_from(request, held)
            issue = True
            if gated and inflight:
                earliest_done, _, running_step = min(inflight)
                after_pool = held + [requests[running_step]]
                cost_after, _ = cost_from(request, after_pool)
                issue = (now + cost_now) <= (earliest_done + cost_after)
                if not issue:
                    waits += 1
            if issue:
                inflight.append((now + cost_now, source_now, step))
                work += cost_now
                step += 1
                continue

        if not inflight:
            break
        inflight.sort()
        finish, source, done_step = inflight.pop(0)
        idle += max(0, finish - now) * max(0, engines - len(inflight) - 1)
        now = max(now, finish)
        retire(source, done_step)

    return now, work, idle, waits


def event_driven_e2(requests, capacity, engines=2, in_flight_cap=2):
    return _schedule(requests, capacity, engines, in_flight_cap, gated=False)[:3]


def event_driven_gated(requests, capacity, engines=2, in_flight_cap=2):
    return _schedule(requests, capacity, engines, in_flight_cap, gated=True)[:3]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    args = parser.parse_args()

    with open(os.path.join(args.out, "logical_traces.json"), encoding="utf-8") as handle:
        traces = json.load(handle)

    budgets = (3, 4, 5)
    rows = []
    for trace in traces:
        requests = [int(v) for v in trace["requested_j"]]
        row = dict(
            target_count=trace["target_count"],
            seed_index=trace["seed_index"],
            requests=len(requests),
        )
        for capacity in budgets:
            work, costs = offline_optimum(requests, capacity, "BRIDGE")
            tag = f"c{capacity}"
            row[f"{tag}_work"] = work
            row[f"{tag}_e1"] = work  # 단일 엔진 makespan = 총작업
            row[f"{tag}_e2"] = list_schedule(costs, 2)
            row[f"{tag}_lb2"] = max((work + 1) // 2, max(costs) if costs else 0)
            row[f"{tag}_maxjob"] = max(costs) if costs else 0
            span, work_ev, idle = event_driven_e2(requests, capacity)
            row[f"{tag}_ev_makespan"] = span
            row[f"{tag}_ev_work"] = work_ev
            row[f"{tag}_ev_idle"] = idle
            span_g, work_g, idle_g = event_driven_gated(requests, capacity)
            row[f"{tag}_gate_makespan"] = span_g
            row[f"{tag}_gate_work"] = work_g
            row[f"{tag}_gate_idle"] = idle_g
        rows.append(row)

    path = os.path.join(args.out, "family1_bound.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    def total(key: str) -> int:
        return sum(r[key] for r in rows)

    print("=== Family 1 낙관적 상한, frozen 250 workload")
    print("    job 비용은 순차 offline optimum. 경합·오버헤드·commit 대기 전부 0\n")
    print(
        f"{'checkpoint':<12} {'총작업':>8} {'E=1 makespan':>13} "
        f"{'E=2 makespan':>13} {'E=2 하한':>10} {'utilization':>12}"
    )
    for capacity in budgets:
        tag = f"c{capacity}"
        work = total(f"{tag}_work")
        e2 = total(f"{tag}_e2")
        print(
            f"{'C%d' % capacity:<12} {work:>8,} {total(f'{tag}_e1'):>13,} "
            f"{e2:>13,} {total(f'{tag}_lb2'):>10,} {100*work/(2*e2):>11.1f}%"
        )

    print("\n=== 가시성 제약을 넣은 event-driven E=2")
    print("    (동시에 도는 job 은 서로가 만든 checkpoint 를 못 봄. 적재/퇴출만 미래를 앎)\n")
    print(
        f"{'checkpoint':<12} {'총작업':>8} {'makespan':>10} "
        f"{'utilization':>12} {'vs 보드':>10}"
    )
    for capacity in budgets:
        tag = f"c{capacity}"
        work_ev = total(f"{tag}_ev_work")
        span = total(f"{tag}_ev_makespan")
        print(
            f"{'C%d' % capacity:<12} {work_ev:>8,} {span:>10,} "
            f"{100*work_ev/(2*span):>11.1f}% "
            f"{100*(span/BOARD_K4_ONLINE-1):>+9.2f}%"
        )

    print("\n=== 선택적 투기 (두 번째 엔진을 이득 있을 때만 씀)\n")
    print(
        f"{'checkpoint':<12} {'총작업':>8} {'makespan':>10} "
        f"{'utilization':>12} {'vs 보드':>10}"
    )
    for capacity in budgets:
        tag = f"c{capacity}"
        work_g = total(f"{tag}_gate_work")
        span_g = total(f"{tag}_gate_makespan")
        print(
            f"{'C%d' % capacity:<12} {work_g:>8,} {span_g:>10,} "
            f"{100*work_g/(2*span_g):>11.1f}% "
            f"{100*(span_g/BOARD_K4_ONLINE-1):>+9.2f}%"
        )

    print(f"\n보드 실측 K4 단일 엔진 = {BOARD_K4_ONLINE:,} (makespan = 총작업)\n")
    print(f"{'checkpoint':<12} {'E=1 vs 보드':>12} {'E=2 vs 보드':>12} {'판정':>8}")
    for capacity in budgets:
        tag = f"c{capacity}"
        d1 = 100 * (total(f"{tag}_e1") / BOARD_K4_ONLINE - 1)
        d2 = 100 * (total(f"{tag}_e2") / BOARD_K4_ONLINE - 1)
        print(
            f"{'C%d' % capacity:<12} {d1:>+11.2f}% {d2:>+11.2f}% "
            f"{'이득' if d2 < 0 else '손해':>8}"
        )

    # makespan 을 무엇이 묶고 있는지
    print("\n=== E=2 makespan 을 묶는 요인 (C4 기준)")
    work = total("c4_work")
    maxjob = total("c4_maxjob")
    print(f"  총작업/2                {work/2:>10,.0f}")
    print(f"  workload 별 최대 job 합 {maxjob:>10,}")
    print(f"  실제 E=2 makespan       {total('c4_e2'):>10,}")
    print(f"\nraw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
