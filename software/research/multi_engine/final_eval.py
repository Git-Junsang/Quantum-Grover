#!/usr/bin/env python3
"""
최종 평가 -- 모든 후보를 **같은 출처**로 다시 냅니다.

앞 단계들은 출처가 섞여 있었습니다. Family 2 의 makespan 은 track 별 offline
optimum(낙관)인데 policy work 는 online DP 실측이었고, Family 1 의 비용열은
탐욕 휴리스틱이었습니다. 여기서는 **전부 restricted-B online DP** 로 통일하고,
compute 와 policy 를 한 이벤트 루프 안에서 같이 굴립니다.

## 모델

엔진 둘을 따로 둡니다.

    datapath 엔진   샷 하나 = 물리반복 x 1,051.7 + 샷 고정비 919.3 사이클
    policy 엔진     결정 하나 = action 수 x 60.89 사이클, **직렬**

policy 엔진은 다음 결정을 미리 풀어 둡니다 (one-shot-ahead Shadow-J). datapath 가
플랜을 필요로 하는 시각에 아직 안 풀렸으면 그만큼 stall 입니다.

    stall_i = max(0, policy_ready_i - engine_free_i)

이 구조가 "엔진을 늘리면 은닉 창이 준다" 를 자동으로 만듭니다. 엔진이 둘이면
datapath 가 플랜을 두 배 빨리 요구하는데 policy 엔진은 그대로라서요.

## 세 가지 배치

    single    엔진 1, 요청 열 하나, policy 1
    F1        엔진 2, 요청 열 하나, 공유 checkpoint pool, policy 1
              동시에 도는 job 은 서로가 만든 checkpoint 를 못 봅니다
    F2        track 2개(짝/홀), 각자 엔진 1 + policy 1 + 자기 checkpoint pool
              cross-track 재사용 금지. makespan = max(track A, track B)

## 보정 (전부 K4/H4 보드 계측)

    반복당 1,051.7 사이클 · 샷 고정비 919.3    250쌍 per-seed 회귀
    결정당 action 79.46 · action 당 4.872 사이클  telemetry 합산
"""
from __future__ import annotations

import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from online_policy import _next_states, make_scorer  # noqa: E402
from policy_work import BOARD_ACT_PER_SOLVE, BOARD_CYC_PER_ACTION  # noqa: E402

CYC_PER_ITER = 1051.7
SHOT_OVH = 919.3
BOARD_CYCLES = 7796908
BOARD_STALL = 276027
BOARD_ITER = 4247

# policy_work.py 에서 잰 모델 결정당 action (K4/H4) -> 보드 79.46 에 맞추는 배율
MODEL_APD_K4H4 = 6.358
SCALE = BOARD_ACT_PER_SOLVE / MODEL_APD_K4H4
CYC_PER_ACTION = SCALE * BOARD_CYC_PER_ACTION


def decide(scorer, held, request, window, capacity):
    """restricted-B DP 한 번. (비용, 다음 보유집합, 평가한 action 수)"""
    best = (1 << 30, 1 << 30)
    pick_source, pick_state = 0, held
    actions = 0
    for source in sorted({0, *[p for p in held if p <= request]}, reverse=True):
        cost = request - source
        for state in _next_states(capacity, held, source, request, window):
            actions += 1
            tail = scorer(state, window)
            cand = (cost + tail[0], int(cost > 0) + tail[1])
            if cand < best:
                best, pick_source, pick_state = cand, source, state
    return request - pick_source, pick_state, actions


def run_serial(requests, capacity, horizon, scorer):
    """엔진 1대. 요청 열 하나. (사이클, 반복, stall, 결정수, action수)"""
    held: tuple[int, ...] = ()
    t = 0.0
    policy_free = 0.0
    work = stall = 0.0
    actions_total = 0
    for index, request in enumerate(requests):
        window = tuple(requests[index + 1 : index + 1 + horizon])
        cost, held, acts = decide(scorer, held, request, window, capacity)
        actions_total += acts
        # policy 엔진은 직렬. 앞 결정이 끝난 뒤에야 이 결정을 시작합니다.
        policy_free = max(policy_free, 0.0) + acts * CYC_PER_ACTION
        wait = max(0.0, policy_free - t)
        stall += wait
        t += wait + cost * CYC_PER_ITER + SHOT_OVH
        # 다음 결정은 이 샷이 도는 동안 풀립니다 -> policy 시작 기준을 당깁니다
        policy_free = max(policy_free, t - cost * CYC_PER_ITER - SHOT_OVH)
        work += cost
    return t, work, stall, len(requests), actions_total


def run_family1(requests, capacity, horizon, scorer, engines=2, cap_inflight=2):
    """엔진 2대가 같은 요청 열을 나눠 처리. checkpoint pool 공유, 가시성 제약."""
    held: tuple[int, ...] = ()
    engine_free = [0.0] * engines
    policy_free = 0.0
    inflight: list[tuple[float, tuple[int, ...]]] = []
    t = 0.0
    work = stall = 0.0
    actions_total = 0
    for index, request in enumerate(requests):
        # 엔진이 빌 때까지, 그리고 in-flight 여유가 생길 때까지 회수합니다.
        engine = min(range(engines), key=lambda i: engine_free[i])
        ready = engine_free[engine]
        while len(inflight) >= cap_inflight or (inflight and inflight[0][0] <= ready):
            inflight.sort()
            fin, state = inflight.pop(0)
            ready = max(ready, fin) if len(inflight) >= cap_inflight else ready
            held = state  # 끝난 job 의 적재가 이제 보입니다
        window = tuple(requests[index + 1 : index + 1 + horizon])
        cost, next_state, acts = decide(scorer, held, request, window, capacity)
        actions_total += acts
        policy_free = max(policy_free, 0.0) + acts * CYC_PER_ACTION
        start = max(ready, policy_free)
        stall += max(0.0, policy_free - ready)
        finish = start + cost * CYC_PER_ITER + SHOT_OVH
        engine_free[engine] = finish
        policy_free = max(policy_free, start)
        inflight.append((finish, next_state))
        work += cost
        t = max(t, finish)
    return t, work, stall, len(requests), actions_total


def run_family2(requests, cap_a, cap_b, horizon, scorer_a, scorer_b):
    """짝/홀 track 이 각자 엔진·policy·pool 을 갖습니다. makespan = max."""
    out = []
    for seq, cap, sc in ((requests[0::2], cap_a, scorer_a), (requests[1::2], cap_b, scorer_b)):
        if not seq:
            out.append((0.0, 0.0, 0.0, 0, 0))
            continue
        out.append(run_serial(seq, cap, horizon, sc))
    span = max(o[0] for o in out)
    return (span,) + tuple(sum(o[i] for o in out) for i in range(1, 5))


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "out", "logical_traces.json"), encoding="utf-8") as h:
        traces = json.load(h)
    all_requests = [[int(v) for v in t["requested_j"]] for t in traces]

    scorers = {k: make_scorer(k) for k in (2, 3, 4, 5, 6)}

    configs = [
        ("K4/H4 (기준선)", "single", dict(capacity=4, horizon=4)),
        ("K4/H6", "single", dict(capacity=4, horizon=6)),
        ("K3/H4", "single", dict(capacity=3, horizon=4)),
        ("K5/H4", "single", dict(capacity=5, horizon=4)),
        ("K6/H4", "single", dict(capacity=6, horizon=4)),
        ("F1 C3+R2", "f1", dict(capacity=3, horizon=4)),
        ("F1 C4+R2", "f1", dict(capacity=4, horizon=4)),
        ("F1 C5+R2", "f1", dict(capacity=5, horizon=4)),
        ("F2 K2+K2", "f2", dict(cap_a=2, cap_b=2, horizon=4)),
        ("F2 K3+K2", "f2", dict(cap_a=3, cap_b=2, horizon=4)),
        ("F2 K2+K3", "f2", dict(cap_a=2, cap_b=3, horizon=4)),
        ("F2 K3+K3", "f2", dict(cap_a=3, cap_b=3, horizon=4)),
    ]

    rows = []
    for name, kind, kw in configs:
        cyc = work = stall = 0.0
        dec = act = 0
        for requests in all_requests:
            if kind == "single":
                r = run_serial(requests, kw["capacity"], kw["horizon"], scorers[kw["capacity"]])
            elif kind == "f1":
                r = run_family1(requests, kw["capacity"], kw["horizon"], scorers[kw["capacity"]])
            else:
                r = run_family2(requests, kw["cap_a"], kw["cap_b"], kw["horizon"],
                                scorers[kw["cap_a"]], scorers[kw["cap_b"]])
            cyc += r[0]; work += r[1]; stall += r[2]; dec += r[3]; act += r[4]
        rows.append(dict(name=name, kind=kind, cycles=cyc, work=work, stall=stall,
                         decisions=dec, actions=act, apd=act / dec * SCALE,
                         engines=1 if kind == "single" else 2))

    base = rows[0]
    print("=== 모델 검증 (K4/H4 단일)")
    print(f"  사이클  모델 {base['cycles']:>12,.0f}   보드 {BOARD_CYCLES:>12,}"
          f"   ({100*(base['cycles']/BOARD_CYCLES-1):+.1f}%)")
    print(f"  반복    모델 {base['work']:>12,.0f}   보드 {BOARD_ITER:>12,}"
          f"   ({100*(base['work']/BOARD_ITER-1):+.1f}%)")
    print(f"  stall   모델 {base['stall']:>12,.0f}   보드 {BOARD_STALL:>12,}"
          f"   ({100*(base['stall']/BOARD_STALL-1):+.1f}%)")
    print(f"  결정당 action 모델 {base['apd']:.2f}   보드 {BOARD_ACT_PER_SOLVE:.2f}")

    print("\n=== 전체 후보 (전부 restricted-B online DP, 같은 이벤트 루프)")
    print(f"{'후보':<16}{'E':>2}{'반복':>8}{'stall':>11}{'사이클':>13}"
          f"{'기준선대비':>11}{'결정당act':>10}{'게이트':>7}")
    print("-" * 82)
    for r in rows:
        r["ratio"] = r["apd"] / base["apd"]
        r["pass"] = r["ratio"] <= 1.0
        gate = "기준선" if r is base else ("통과" if r["pass"] else "탈락")
        print(f"{r['name']:<16}{r['engines']:>2}{r['work']:>8,.0f}{r['stall']:>11,.0f}"
              f"{r['cycles']:>13,.0f}{100*(r['cycles']/base['cycles']-1):>10.2f}%"
              f"{r['apd']:>10.2f}{gate:>7}")

    print("\n=== 게이트 통과분만, 사이클 오름차순")
    surv = sorted([r for r in rows if r["pass"]], key=lambda r: r["cycles"])
    print(f"{'#':>2} {'후보':<16}{'E':>2}{'사이클':>13}{'기준선대비':>11}{'stall':>11}{'반복':>8}")
    print("-" * 66)
    for i, r in enumerate(surv, 1):
        print(f"{i:>2} {r['name']:<16}{r['engines']:>2}{r['cycles']:>13,.0f}"
              f"{100*(r['cycles']/base['cycles']-1):>10.2f}%{r['stall']:>11,.0f}{r['work']:>8,.0f}")

    path = os.path.join(here, "out", "final_eval.csv")
    with open(path, "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=["name", "kind", "engines", "work", "stall",
                                          "cycles", "decisions", "actions", "apd",
                                          "ratio", "pass"])
        w.writeheader(); w.writerows(rows)
    print(f"\nraw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
