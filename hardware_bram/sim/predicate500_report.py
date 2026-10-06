#!/usr/bin/env python3
"""
predicate500_report.py -- Predicate500 RTL 벤치 CSV 를 SW 기준모델 기댓값과 맞댑니다.

입력은 tb_predicate500.cpp(bram) 또는 tb_dram_predicate500.v(dram) 가 낸 CSV
하나 이상입니다. 한 줄이 한 실행이고 열은
    predicate,m,seed_idx,mode,rc,result_index,result_value,trial,l_bbht,iter,cycles,status
입니다.

기댓값은 software/experiments/predicate500_benchmark/expected/
predicate500_expected.csv 입니다 (run_predicate500_golden.py 가 만듦).

실행 하나마다 여섯 축을 봅니다.
    rc            정상 종료했고 해를 찾았는가 (기댓값 success 와 같은가)
    result_index  같은 인덱스를 냈는가
    술어          그 인덱스의 값이 정말 술어를 만족하는가 (고전 검증)
    trial_count   BBHT 시도 수
    L_BBHT        요청한 j 의 합 (알고리즘 지표)
    actual_iter   물리 반복. 모드에 맞는 열과 맞댑니다
                    bram normal -> actual_iter_normal
                    bram ckpt   -> actual_iter_k3h3
                    dram normal -> actual_iter_dram_session
                    nocheckpoint normal -> actual_iter_normal
                      (hardware_bram_nocheckpoint. 체크포인트가 없으니 NORMAL 과
                      같은 물리 반복입니다)
                  dram 은 적재한 데이터셋 하나에서 시드를 차례로 돌며 DRAM 표를
                  이어 씁니다. 그래서 탐색마다 표를 비운 DRAM_ALL_J 가 아니라
                  같은 순서로 표를 이어 쓴 session 열과 맞댑니다

사이클은 기준모델에 없으므로 맞대지 않고 모드별 합만 보고합니다.

사용법:
    python3 predicate500_report.py [--branch bram|dram|nocheckpoint] CSV [CSV ...]
종료 코드는 불일치가 하나라도 있으면 1 입니다.
"""
import argparse
import csv
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir))
EXPECTED = os.path.join(REPO, "software", "experiments", "predicate500_benchmark",
                        "expected", "predicate500_expected.csv")

ORDER = ("LT", "GT", "EQ", "RANGE")
ITER_COLUMN = {
    ("bram", "normal"): "actual_iter_normal",
    ("bram", "ckpt"):   "actual_iter_k3h3",
    ("dram", "normal"): "actual_iter_dram_session",
    ("nocheckpoint", "normal"): "actual_iter_normal",
}


def pred_ok(p, v, a, b):
    if p == "LT":
        return v < a
    if p == "GT":
        return v > a
    if p == "EQ":
        return v == a
    return a < v < b


def main():
    ap = argparse.ArgumentParser(description="Predicate500 RTL 대 SW 기댓값")
    ap.add_argument("--branch", choices=("bram", "dram", "nocheckpoint"), default="bram")
    ap.add_argument("--expected", default=EXPECTED)
    ap.add_argument("--partial", action="store_true",
                    help="일부 워크로드만 돌린 시험 실행. 빠진 실행을 실패로 보지 않습니다")
    ap.add_argument("csv", nargs="+")
    args = ap.parse_args()

    with open(args.expected, encoding="utf-8") as f:
        exp = {(r["predicate"], int(r["target_count"]), int(r["seed_index"])): r
               for r in csv.DictReader(f)}

    rows = []
    for path in args.csv:
        with open(path, encoding="utf-8") as f:
            rows += [r for r in csv.DictReader(
                         line for line in f if line.strip() and not line.startswith("#"))
                     if r.get("predicate")]

    axes = ("rc", "result_index", "predicate", "trial_count", "L_BBHT", "actual_iter")
    ok = defaultdict(lambda: defaultdict(int))
    total = defaultdict(int)
    cycles = defaultdict(int)
    iters = defaultdict(int)
    first_bad = []
    seen = set()

    for r in rows:
        p, m, s, mode = r["predicate"], int(r["m"]), int(r["seed_idx"]), r["mode"]
        e = exp.get((p, m, s))
        if e is None:
            first_bad.append("기댓값에 없는 워크로드 %s M=%d seed=%d" % (p, m, s))
            continue
        key = (p, mode)
        seen.add((p, m, s, mode))
        total[key] += 1
        found = r["rc"] == "OK"
        a, b = int(e["threshold_a"]), int(e["threshold_b"])
        col = ITER_COLUMN.get((args.branch, mode))
        checks = {
            "rc":           found == bool(int(e["success"])),
            "result_index": (int(r["result_index"]) if found else -1)
                            == (int(e["result_index"]) if e["result_index"] != "" else -1),
            "predicate":    (not found) or pred_ok(p, int(r["result_value"]), a, b),
            "trial_count":  int(r["trial"]) == int(e["trial_count"]),
            "L_BBHT":       int(r["l_bbht"]) == int(e["L_BBHT"]),
            "actual_iter":  col is not None and int(r["iter"]) == int(e[col]),
        }
        for k, v in checks.items():
            ok[key][k] += int(v)
        if not all(checks.values()) and len(first_bad) < 20:
            bad = [k for k, v in checks.items() if not v]
            first_bad.append("%s M=%d seed=%d %s: %s  (rtl idx=%s trial=%s l=%s iter=%s / "
                             "sw idx=%s trial=%s l=%s iter=%s)"
                             % (p, m, s, mode, ",".join(bad), r["result_index"], r["trial"],
                                r["l_bbht"], r["iter"], e["result_index"], e["trial_count"],
                                e["L_BBHT"], e[col] if col else "?"))
        cycles[key] += int(r["cycles"])
        iters[key] += int(r["iter"])

    modes = sorted({k[1] for k in total}, key=lambda x: (x != "normal", x))
    print("Predicate500 %s RTL 대 SW 기준모델 (%s)" % (args.branch, os.path.relpath(args.expected, REPO)))
    print("%-6s %-7s %5s  %s" % ("술어", "모드", "실행", "  ".join("%-12s" % a for a in axes)))
    all_ok = True
    for p in ORDER:
        for mode in modes:
            key = (p, mode)
            if not total[key]:
                continue
            n = total[key]
            cells = []
            for a in axes:
                cells.append("%-12s" % ("%d/%d" % (ok[key][a], n)))
                all_ok &= ok[key][a] == n
            print("%-6s %-7s %5d  %s" % (p, mode, n, "  ".join(cells)))

    print("")
    print("사이클 합 (clk_accel 100 MHz)")
    for p in ORDER:
        line = []
        for mode in modes:
            if total[(p, mode)]:
                line.append("%s %d cyc / iter %d" % (mode, cycles[(p, mode)], iters[(p, mode)]))
        if len(modes) == 2 and total[(p, "normal")] and total[(p, modes[1])] and cycles[(p, modes[1])]:
            line.append("normal/%s %.4fx" % (modes[1], cycles[(p, "normal")] / cycles[(p, modes[1])]))
        if line:
            print("  %-6s %s" % (p, "  |  ".join(line)))

    # 돌린 술어 안에서만 빠진 것을 셉니다. PRED500_PREDS 로 술어 일부만 돌리는
    # 것은 정상 사용법입니다.
    run_preds = {k[0] for k in total}
    want = {(p, m, s, mode) for (p, m, s) in exp if p in run_preds for mode in modes}
    missing = len(want - seen)
    if missing:
        print("\n빠진 실행 %d 개 (벤치가 중간에 끊겼거나 술어를 일부만 돌림)" % missing)
        if not args.partial:
            all_ok = False

    if first_bad:
        print("\n불일치 (앞 20개)")
        for line in first_bad:
            print("  " + line)
    print("\n판정: %s" % ("PASS" if all_ok and not first_bad and rows else "FAIL"))
    return 0 if all_ok and not first_bad and rows else 1


if __name__ == "__main__":
    sys.exit(main())
