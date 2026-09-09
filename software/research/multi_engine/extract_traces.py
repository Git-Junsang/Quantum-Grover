#!/usr/bin/env python3
"""
frozen 250 workload 의 논리 BBHT trace 를 뽑습니다.

이후 모든 실험(offline optimum, parity 검산, Family 1/2 시뮬레이터)이 **같은**
trace 위에서 돌아야 합니다 (연구 지시 16절 same-workload fairness). 그래서
trace 추출을 한 번만 하고 파일로 굳혀 둡니다.

trace 는 checkpoint 를 켠 실행이 아니라 논리 층에서 나옵니다. 250/250 에서
Normal 과 checkpoint 의 논리 튜플이 같다는 것을 baseline_repro.py 가 이미
확인했으므로, 어느 쪽에서 뽑아도 같은 시퀀스입니다. 여기서는 checkpoint 실행에서
뽑아 physical/source 기록까지 같이 남깁니다.

  requested_j    각 trial 이 요청한 논리 j (BBHT 가 정하는 것. 아키텍처가
                 바꾸면 안 되는 값)
  success        그 trial 의 Born 측정이 타겟을 맞췄는지
  m_bound        그 round 의 m 상한

Normal 모드의 물리 반복은 sum(requested_j) 와 같습니다. 이게 이후 비용 모델의
기준선입니다.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
import sys
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "software", "golden"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rtl_v098_auto  # noqa: E402
from rtl_v098_auto import V098AutomaticCore  # noqa: E402
from rtl_v098_data import build_official_board_benchmark_dataset  # noqa: E402

from rtl_meas_prng import install as install_rtl_measurement  # noqa: E402

TARGET_COUNTS = (1, 4, 16, 64, 256)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument(
        "--roster",
        default=os.path.join(os.path.dirname(__file__), "seed_roster_50.json"),
    )
    args = parser.parse_args()

    install_rtl_measurement()
    os.makedirs(args.out, exist_ok=True)
    with open(args.roster, encoding="utf-8") as handle:
        roster = [(int(a), int(b)) for a, b in json.load(handle)]

    started = time.time()
    traces = []
    for target_count in TARGET_COUNTS:
        dataset = build_official_board_benchmark_dataset(target_count)
        for seed_index, (seed_j, seed_meas) in enumerate(roster):
            cfg = dataclasses.replace(
                dataset.config,
                seed_j=seed_j,
                seed_meas=seed_meas,
                shot_cap=100,
                burst_enable=True,
                enum_enable=False,
            )
            result = V098AutomaticCore(dataset, cfg).run_single(mode="CKPT")
            traces.append(
                dict(
                    target_count=target_count,
                    seed_index=seed_index,
                    seed_j=seed_j,
                    seed_meas=seed_meas,
                    success=bool(result.success),
                    trial_count=result.trial_count,
                    L_BBHT=result.L_BBHT,
                    result_index=result.result_index,
                    requested_j=[int(a.requested_j) for a in result.attempts],
                    trial_success=[bool(a.success) for a in result.attempts],
                    m_bound=[int(a.m_bound) for a in result.attempts],
                    golden_ckpt_physical=result.actual_grover_iterations,
                )
            )

    # 무결성 확인. 논리 semantics 가 깨지면 여기서 멈춥니다.
    for trace in traces:
        if len(trace["requested_j"]) != trace["trial_count"]:
            sys.exit("trial_count 와 requested_j 길이가 다릅니다")
        if sum(trace["requested_j"]) != trace["L_BBHT"]:
            sys.exit("sum(requested_j) != L_BBHT")
        if trace["success"] != trace["trial_success"][-1]:
            sys.exit("마지막 trial 의 성공 여부가 결과와 다릅니다")
        if any(trace["trial_success"][:-1]):
            sys.exit("마지막이 아닌 trial 이 성공으로 기록되었습니다")

    path = os.path.join(args.out, "logical_traces.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(traces, handle)

    total_requests = sum(t["trial_count"] for t in traces)
    total_L = sum(t["L_BBHT"] for t in traces)
    print(f"workload            {len(traces)}")
    print(f"논리 요청 총 개수   {total_requests}")
    print(f"sum(requested_j)    {total_L}   (= Normal 물리 반복)")
    print(f"성공                {sum(t['success'] for t in traces)}/{len(traces)}")
    print(f"trial 최대/평균     {max(t['trial_count'] for t in traces)} / "
          f"{total_requests/len(traces):.2f}")
    print(f"요청 j 최대         {max(max(t['requested_j']) for t in traces)}")
    print(f"\n{path}  ({time.time()-started:.1f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
