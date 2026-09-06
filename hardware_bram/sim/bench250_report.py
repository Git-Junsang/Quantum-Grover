#!/usr/bin/env python3
"""
250쌍 벤치 결과를 집계하고 궤적 불변량을 검사합니다.

    bench250_report.py <csv>              한 갈래 집계 + 보드 대조
    bench250_report.py <base.csv> <cmp.csv>  두 갈래 교차 검증까지

불변량이 핵심입니다. checkpoint 는 psi 를 어떻게 계산하느냐만 바꾸므로,
trial_count 와 L_BBHT 는 Normal 과 K4 가 같아야 합니다. 계산 순서만 바꾸는
최적화(PASS2 융합 등)도 두 갈래 사이에서 이 둘이 같아야 합니다.

result_index 로는 판정할 수 없습니다. BBHT 가 후보를 술어로 자가 검증하므로
진폭이 깨져도 답은 맞게 나옵니다.
"""
import csv
import sys

# 보드 실측 2026-09-04 (MEASURED).
BOARD = dict(n_iter=14883, n_cyc=20229755, k_iter=4247, k_cyc=7796908,
             stall=276027, trial=3647)

FIELDS = ("trial", "l_bbht", "iter", "result_index")


def load(path):
    with open(path, encoding="utf-8") as handle:
        rows = [r for r in csv.DictReader(l for l in handle if not l.startswith("#"))]
    return {(int(r["m"]), int(r["seed_idx"]), r["mode"]): r for r in rows}


def total(rows, mode, field):
    return sum(int(r[field]) for k, r in rows.items() if k[2] == mode)


def report(name, rows):
    n = {f: total(rows, "normal", f) for f in ("iter", "cycles", "trial")}
    k = {f: total(rows, "k4", f)
         for f in ("iter", "cycles", "policy_stall", "policy_cycles",
                   "policy_actions", "mismatch")}
    print(f"\n=== {name} ===")
    print(f"  총 샷          {n['trial']:>12,}")
    print(f"  Normal 반복    {n['iter']:>12,}   사이클 {n['cycles']:>12,}")
    print(f"  K4 반복        {k['iter']:>12,}   사이클 {k['cycles']:>12,}")
    print(f"  반복 감소 {100 * (1 - k['iter'] / n['iter']):.2f}%"
          f"   사이클 감소 {100 * (1 - k['cycles'] / n['cycles']):.2f}%")
    print(f"  policy stall   {k['policy_stall']:>12,}"
          f"  ({100 * k['policy_stall'] / k['cycles']:.2f}% of K4)")
    print(f"  plan_fifo_mismatch {k['mismatch']}  (0 이어야 합니다)")
    return n, k


def check_paired(name, rows):
    bad = [k[:2] for k in rows
           if k[2] == "k4"
           and any(rows[k][f] != rows[(k[0], k[1], "normal")][f]
                   for f in ("trial", "l_bbht"))]
    mark = "ok  " if not bad else "FAIL"
    print(f"  {mark} [{name}] Normal vs K4 궤적  {250 - len(bad)}/250 일치"
          + (f"  어긋난 곳 {bad[:5]}" if bad else ""))
    return len(bad)


def check_cross(base, cmp_):
    fails = 0
    for mode in ("normal", "k4"):
        bad = [k[:2] for k in base
               if k[2] == mode and any(base[k][f] != cmp_[k][f] for f in FIELDS)]
        mark = "ok  " if not bad else "FAIL"
        print(f"  {mark} [{mode}] 두 갈래 궤적  {250 - len(bad)}/250 일치"
              + (f"  어긋난 곳 {bad[:5]}" if bad else ""))
        fails += len(bad)
    return fails


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2

    base = load(sys.argv[1])
    n, k = report(sys.argv[1], base)

    print("\n=== 궤적 불변량 ===")
    fails = check_paired(sys.argv[1], base)

    if len(sys.argv) == 2:
        print("\n=== 보드 실측(2026-09-04) 대조 ===")
        print(f"{'항목':<16}{'보드':>13}{'시뮬':>13}{'오차':>9}")
        for label, board, sim in (
                ("Normal 반복", BOARD["n_iter"], n["iter"]),
                ("Normal 사이클", BOARD["n_cyc"], n["cycles"]),
                ("K4 반복", BOARD["k_iter"], k["iter"]),
                ("K4 사이클", BOARD["k_cyc"], k["cycles"]),
                ("policy stall", BOARD["stall"], k["policy_stall"]),
                ("총 샷", BOARD["trial"], n["trial"])):
            print(f"{label:<16}{board:>13,}{sim:>13,}{100 * (sim / board - 1):>8.2f}%")
    else:
        cmp_ = load(sys.argv[2])
        n2, k2 = report(sys.argv[2], cmp_)
        fails += check_paired(sys.argv[2], cmp_)
        fails += check_cross(base, cmp_)
        print("\n=== 두 갈래 사이클 비교 ===")
        print(f"  Normal {n['cycles']:>12,} -> {n2['cycles']:>12,}"
              f"  {100 * (n2['cycles'] / n['cycles'] - 1):+.2f}%")
        print(f"  K4     {k['cycles']:>12,} -> {k2['cycles']:>12,}"
              f"  {100 * (k2['cycles'] / k['cycles'] - 1):+.2f}%")
        print(f"  샷당 절감  Normal {(n['cycles'] - n2['cycles']) / n['trial']:.1f}"
              f"   K4 {(k['cycles'] - k2['cycles']) / n['trial']:.1f}")

    print(f"\n{'통과' if fails == 0 else f'실패 {fails}건'}")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
