#!/usr/bin/env python3
"""
Frozen Single K4/H4 baseline reproduction.

2026-09-01 보드 벤치마크와 **완전히 같은** 250 workload 를 소프트웨어 골든
모델로 다시 돌립니다. Family 1/2 DSE 를 시작하기 전에 반드시 통과해야 하는
관문입니다 (연구 지시 0절 · 19절 STOP RULE).

workload 정의는 보드 앱 패키지(bench_app.zip)에서 그대로 가져옵니다.
  데이터셋   build_official_board_benchmark_dataset(M), M in {1,4,16,64,256}
             background seed 0x5EED1234 / target position seed 0xA17E2026
             frozen tools/reference_dataset/*.bin 과 바이트 일치 확인 완료
  시드       seed_roster.h 의 앞 50쌍 (BENCH_SEED_COUNT=50)
  술어       EQ(12345), DATA_COUNT=16384, SHOT_CAP=100
  모드       Normal(auto=1,burst=0) 과 checkpoint(auto=1,burst=1)

horizon 은 명령행으로 고릅니다. 저장소의 골든 모델 상수
V098_POLICY_HORIZON 은 8 인데 src_v2 실물 RTL 의 policy 는 H_FUTURE=4 라,
어느 쪽이 보드 실측을 재현하는지 이 스크립트로 가립니다. 골든 모델 파일은
고치지 않고 모듈 전역만 갈아 끼웁니다.

    python3 baseline_repro.py --horizon 4 --out out/
"""
from __future__ import annotations

import argparse
import csv
import dataclasses
import json
import os
import sys
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "software", "golden"))

import rtl_v098_auto  # noqa: E402
from rtl_v098_auto import V098AutomaticCore  # noqa: E402
from rtl_v098_data import build_official_board_benchmark_dataset  # noqa: E402

from rtl_meas_prng import install as install_rtl_measurement  # noqa: E402

TARGET_COUNTS = (1, 4, 16, 64, 256)

# 보드 실측 정본 (2026-09-01 50-seed paired benchmark, summary.csv).
BOARD = {
    1: dict(normal_iter=8414, k4_iter=2230, normal_cycles=10186883, k4_cycles=6443381),
    4: dict(normal_iter=3615, k4_iter=1007, normal_cycles=4940549, k4_cycles=3717106),
    16: dict(normal_iter=1882, k4_iter=532, normal_cycles=2920180, k4_cycles=2099548),
    64: dict(normal_iter=662, k4_iter=234, normal_cycles=1359349, k4_cycles=1015193),
    256: dict(normal_iter=310, k4_iter=131, normal_cycles=822794, k4_cycles=549578),
}


def load_roster(path: str) -> list[tuple[int, int]]:
    with open(path, encoding="utf-8") as handle:
        return [(int(a), int(b)) for a, b in json.load(handle)]


def run_all(horizon: int, roster: list[tuple[int, int]]) -> list[dict]:
    """250 workload 를 Normal 과 checkpoint 두 모드로 돌립니다."""
    # 골든 모델의 provisional 측정 PRNG 를 RTL 식으로 갈아 끼웁니다.
    # 이게 없으면 checkpoint 를 끄고 돌린 Normal 조차 보드와 안 맞습니다.
    install_rtl_measurement()
    rtl_v098_auto.V098_POLICY_HORIZON = int(horizon)
    rtl_v098_auto._rolling_score.cache_clear()
    rows: list[dict] = []
    for target_count in TARGET_COUNTS:
        dataset = build_official_board_benchmark_dataset(target_count)
        for seed_index, (seed_j, seed_meas) in enumerate(roster):
            base = dataclasses.replace(
                dataset.config,
                seed_j=seed_j,
                seed_meas=seed_meas,
                shot_cap=100,
                enum_enable=False,
            )
            row = dict(
                target_count=target_count,
                seed_index=seed_index,
                seed_j=seed_j,
                seed_meas=seed_meas,
            )
            for mode, burst in (("normal", False), ("ckpt", True)):
                cfg = dataclasses.replace(base, burst_enable=burst)
                core = V098AutomaticCore(dataset, cfg)
                result = core.run_single(mode="K4H8" if burst else "NORMAL")
                row[f"{mode}_success"] = int(result.success)
                row[f"{mode}_trial"] = result.trial_count
                row[f"{mode}_L"] = result.L_BBHT
                row[f"{mode}_phys"] = result.actual_grover_iterations
                row[f"{mode}_index"] = (
                    -1 if result.result_index is None else result.result_index
                )
                # 논리 튜플. 두 모드가 같아야 checkpoint 가 논리를 안 건드린 것입니다.
                row[f"{mode}_logical"] = "%d/%d/%d" % (
                    result.trial_count,
                    result.L_BBHT,
                    -1 if result.result_index is None else result.result_index,
                )
            rows.append(row)
    return rows


def summarize(rows: list[dict]) -> dict:
    out = {}
    for target_count in TARGET_COUNTS:
        subset = [r for r in rows if r["target_count"] == target_count]
        out[target_count] = dict(
            seeds=len(subset),
            normal_success=sum(r["normal_success"] for r in subset),
            ckpt_success=sum(r["ckpt_success"] for r in subset),
            normal_iter=sum(r["normal_phys"] for r in subset),
            ckpt_iter=sum(r["ckpt_phys"] for r in subset),
            normal_trial=sum(r["normal_trial"] for r in subset),
            ckpt_trial=sum(r["ckpt_trial"] for r in subset),
            normal_L=sum(r["normal_L"] for r in subset),
            ckpt_L=sum(r["ckpt_L"] for r in subset),
            logical_match=sum(
                1 for r in subset if r["normal_logical"] == r["ckpt_logical"]
            ),
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--horizon", type=int, default=4)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument(
        "--roster",
        default=os.path.join(os.path.dirname(__file__), "seed_roster_50.json"),
    )
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    roster = load_roster(args.roster)
    if len(roster) != 50:
        sys.exit("seed roster 는 50쌍이어야 합니다 (BENCH_SEED_COUNT=50)")

    started = time.time()
    rows = run_all(args.horizon, roster)
    elapsed = time.time() - started

    raw_path = os.path.join(args.out, f"baseline_h{args.horizon}_raw.csv")
    with open(raw_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    summary = summarize(rows)
    print(f"=== frozen 250 workload 재현 (H={args.horizon}, {elapsed:.1f}s)")
    print(
        f"{'M':>4} {'seeds':>5} {'Nsucc':>5} {'Csucc':>5} "
        f"{'N iter':>8} {'C iter':>8} | {'board N':>8} {'board C':>8} {'판정':>6}"
    )
    total_n = total_c = 0
    ok = True
    for target_count in TARGET_COUNTS:
        s = summary[target_count]
        b = BOARD[target_count]
        match = s["normal_iter"] == b["normal_iter"] and s["ckpt_iter"] == b["k4_iter"]
        ok = ok and match
        total_n += s["normal_iter"]
        total_c += s["ckpt_iter"]
        print(
            f"{target_count:>4} {s['seeds']:>5} {s['normal_success']:>5} "
            f"{s['ckpt_success']:>5} {s['normal_iter']:>8} {s['ckpt_iter']:>8} | "
            f"{b['normal_iter']:>8} {b['k4_iter']:>8} {'일치' if match else '불일치':>6}"
        )
    board_n = sum(BOARD[m]["normal_iter"] for m in TARGET_COUNTS)
    board_c = sum(BOARD[m]["k4_iter"] for m in TARGET_COUNTS)
    print(
        f"{'합계':>4} {'':>5} {'':>5} {'':>5} {total_n:>8} {total_c:>8} | "
        f"{board_n:>8} {board_c:>8}"
    )
    logical = sum(summary[m]["logical_match"] for m in TARGET_COUNTS)
    print(f"논리 튜플 (trial/L/result) Normal == checkpoint : {logical}/250")

    summary_path = os.path.join(args.out, f"baseline_h{args.horizon}_summary.json")
    with open(summary_path, "w", encoding="utf-8") as handle:
        json.dump(
            dict(
                horizon=args.horizon,
                elapsed_s=elapsed,
                per_target={str(k): v for k, v in summary.items()},
                total_normal_iter=total_n,
                total_ckpt_iter=total_c,
                board_total_normal_iter=board_n,
                board_total_ckpt_iter=board_c,
                exact_match=ok,
                logical_tuple_match=logical,
            ),
            handle,
            indent=2,
        )
    print(f"\nraw     {raw_path}")
    print(f"summary {summary_path}")
    print("\n판정:", "EXACT MATCH" if ok else "MISMATCH")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
