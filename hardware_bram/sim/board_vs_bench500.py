#!/usr/bin/env python3
"""
보드에서 bbht_paper_bench 로 잰 500런을 같은 모델의 RTL bench500 과 워크로드마다 맞댑니다.

    board_vs_bench500.py <보드 결과> --configuration <모델> [--bench <bench500 CSV>]

<보드 결과> 는 둘 중 하나입니다.
  - UART 로그 그대로. HW_REALTIME_CSV 줄만 골라 읽습니다
    (firmware/bbht_paper_bench/tools/parse_benchmark.py 의 해석을 그대로 씁니다)
  - 그 도구가 낸 *.raw.csv, 또는 보드 실측 묶음의 per_run_*.csv (열 구성이 같음)

--bench 를 주지 않으면 results/2026-10-07_bench500_6models/<모델 소문자>.csv 를 씁니다.
이 벤치는 보드 앱과 같은 순서(타겟 수 바깥 · 시드 안쪽 · 시드마다 Normal 다음 체크포인트,
리셋 없이 연달아)로 돌기 때문에, 같은 비트스트림이면 사이클까지 같아야 합니다. 최종
모델에서 2026-09-08 보드 500런과 500/500 맞은 것이 그 근거입니다.

판정
  - 논리 넷(result_index · trial_count · L_BBHT · actual_iter)이 하나라도 어긋나면 실패
  - cycle_count 는 일치 수와 합계를 보여 줍니다. --strict-cycles 를 주면 어긋난 사이클도
    실패로 셉니다
  - 보드의 status 에 timeout · unexpected_error 가 있으면 실패
실경과 시간(elapsed_us)은 보드에만 있는 값이라 모드별 합계만 보여 줍니다. 콘솔의 us= 같은
사이클 환산값과 섞지 마십시오.
"""
import argparse
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, os.pardir, "firmware", "bbht_paper_bench", "tools"))
from parse_benchmark import parse_rows  # noqa: E402  보드 앱 로그의 정본 해석기
from pathlib import Path  # noqa: E402

BENCH_DIR = os.path.join(HERE, os.pardir, "results", "2026-10-07_bench500_6models")
# 구성 이름 -> 그 묶음의 기록 파일 이름(기록은 2026-10-07 당시 이름 그대로)
RECORD_NAME = {"capacity4_lookahead4_pes1_singlerow_linear": "k4h4_e1",
               "capacity3_lookahead3_pes1_singlerow_linear": "k3h3_e1",
               "capacity4_lookahead4_pes4_singlerow_linear": "k4h4_e4",
               "capacity3_lookahead3_pes4_singlerow_linear": "k3h3_e4",
               "capacity3_lookahead3_pes4_dualrow_linear": "k3h3_e4_m1",
               "final": "k3h3_e4_m2"}
CONFIGURATIONS = tuple(RECORD_NAME)

# (보고 이름, 보드 열, bench500 열)
LOGIC = (("result_index", "result_index", "result_index"),
         ("trial_count", "trial_count", "trial"),
         ("L_BBHT", "l_bbht", "l_bbht"),
         ("actual_iter", "actual_iter", "iter"))
# 보드 mode 번호 -> bench500 mode 이름. bench500 은 체크포인트 모드를 옛 이름 k4 로 적습니다.
MODE = {0: "normal", 1: "k4"}
MODE_LABEL = {0: "mode0 NORMAL", 1: "mode1 체크포인트"}


def load_board(path):
    with open(path, encoding="utf-8", errors="ignore") as handle:
        head = handle.readline()
    if head.startswith("target_count,"):
        with open(path, encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        for r in rows:
            for k, v in r.items():
                if v is not None and v.lstrip("-").isdigit():
                    r[k] = int(v)
        return rows
    return parse_rows(Path(path))


def load_bench(path):
    with open(path, encoding="utf-8") as handle:
        rows = [r for r in csv.DictReader(l for l in handle if not l.startswith("#"))]
    return {(int(r["m"]), int(r["seed_idx"]), r["mode"]): r for r in rows}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("board")
    ap.add_argument("--configuration", required=True, choices=CONFIGURATIONS)
    ap.add_argument("--bench")
    ap.add_argument("--strict-cycles", action="store_true")
    a = ap.parse_args()

    bench_path = a.bench or os.path.join(BENCH_DIR, RECORD_NAME[a.configuration] + ".csv")
    board = load_board(a.board)
    bench = load_bench(bench_path)
    print(f"구성 {a.configuration}")
    print(f"  보드   {a.board}  ({len(board)}행)")
    print(f"  벤치   {os.path.normpath(bench_path)}")

    fails = 0
    # A truncated UART capture must not pass because there are no rows left
    # to compare. Require the same complete workload/mode set as the RTL CSV.
    expected = {(m, seed, 0 if mode == "normal" else 1) for m, seed, mode in bench}
    actual = [(int(r["target_count"]), int(r["seed_index"]), int(r["mode"])) for r in board]
    if len(board) != len(bench) or len(set(actual)) != len(actual) or set(actual) != expected:
        print(f"  FAIL workload coverage: board={len(board)}, expected={len(bench)}, "
              f"unique={len(set(actual))}, missing={len(expected-set(actual))}, extra={len(set(actual)-expected)}")
        fails += 1
    errs = [r for r in board if int(r.get("timeout", 0)) or int(r.get("unexpected_error", 0))]
    if errs:
        print(f"  FAIL 보드 오류 행 {len(errs)}개 (timeout 또는 unexpected_error)")
        fails += len(errs)

    for mode in (0, 1):
        rows = [r for r in board if int(r["mode"]) == mode]
        pairs = [(r, bench.get((int(r["target_count"]), int(r["seed_index"]), MODE[mode]))) for r in rows]
        missing = sum(1 for _, b in pairs if b is None)
        pairs = [(r, b) for r, b in pairs if b is not None]
        print(f"\n=== {MODE_LABEL[mode]} ({len(pairs)}쌍"
              + (f", 벤치에 없는 보드 행 {missing}" if missing else "") + ") ===")
        if missing:
            fails += missing
        if not pairs:
            continue
        for label, bf, sf in LOGIC:
            hit = sum(int(r[bf]) == int(b[sf]) for r, b in pairs)
            print(f"  {'ok  ' if hit == len(pairs) else 'FAIL'} {label:<14}{hit:>4}/{len(pairs)}")
            fails += len(pairs) - hit
        same = sum(int(r["cycle_count"]) == int(b["cycles"]) for r, b in pairs)
        tb = sum(int(r["cycle_count"]) for r, _ in pairs)
        ts = sum(int(b["cycles"]) for _, b in pairs)
        mark = "ok  " if same == len(pairs) else ("FAIL" if a.strict_cycles else "    ")
        print(f"  {mark} cycle_count   {same:>4}/{len(pairs)}  합계 보드 {tb:,} 대 벤치 {ts:,}"
              f" ({100 * (tb / ts - 1):+.2f}%)")
        if a.strict_cycles:
            fails += len(pairs) - same
        if "elapsed_us" in pairs[0][0]:
            print(f"       실경과 합 {sum(int(r['elapsed_us']) for r, _ in pairs):,} us (보드 축)")

    print("\n통과" if fails == 0 else f"\n실패 {fails}건")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
