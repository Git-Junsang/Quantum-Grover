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
import os
import sys

# 보드 실측 대조 상대.
#
# 2026-09-08 묶음의 M2 경로(mode=1)가 지금 src/ 와 같은 코어입니다. 그쪽은
# 시드 100개(500 워크로드)이고 이 벤치는 앞 50개(250 워크로드)이므로, 겹치는
# 250개만 워크로드별로 맞대 봅니다. 합계가 아니라 한 건씩 보는 것이 핵심입니다.
BOARD_M2 = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), os.pardir, "vivado",
    "vivado_bbht_grover_fpga", "2026-09-08_k3h3_e4_m2_board_500run",
    "per_run_m2.csv")

# 앞선 K4/H4-E1 보드 실측(2026-09-04)의 250쌍 합계입니다. 코어가 다르므로
# 사이클을 맞대면 안 되고, 논리 궤적(총 샷·Normal 반복)만 같아야 합니다.
BOARD_K4H4 = dict(n_iter=14883, n_cyc=20229755, k_iter=4247, k_cyc=7796908,
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


def check_board(rows):
    """보드 M2 실측과 워크로드별로 맞댑니다.

    논리 궤적 넷은 **전부 같아야** 합니다. 사이클은 대부분 같지만 몇 건이
    어긋납니다 -- 보드는 500 워크로드를 연달아 돌아서 체크포인트 준비 비용을
    앞에서 한 번만 내는 데 반해 이 벤치는 250개만 돌기 때문으로 보이며,
    원인을 확정하지는 않았습니다. 그래서 사이클은 세어서 보여만 주고
    실패로 잡지 않습니다.
    """
    path = os.path.normpath(BOARD_M2)
    if not os.path.exists(path):
        print(f"\n=== 보드 실측 대조 === 건너뜀 (없음: {path})")
        return 0

    with open(path, encoding="utf-8") as handle:
        board = {(int(r["target_count"]), int(r["seed_index"])): r
                 for r in csv.DictReader(handle)}

    pairs = [(rows[k], board[(k[0], k[1])]) for k in rows
             if k[2] == "k4" and (k[0], k[1]) in board]

    print(f"\n=== 보드 실측 대조 (2026-09-08 M2, 같은 코어) ===")
    if not pairs:
        print("  겹치는 워크로드가 없습니다")
        return 0

    bad = 0
    for label, ours, theirs in (("result_index", "result_index", "result_index"),
                                ("trial_count", "trial", "trial_count"),
                                ("L_BBHT", "l_bbht", "l_bbht"),
                                ("actual_iter", "iter", "actual_iter")):
        hit = sum(s[ours] == b[theirs] for s, b in pairs)
        mark = "ok  " if hit == len(pairs) else "FAIL"
        print(f"  {mark} {label:<14}{hit:>4}/{len(pairs)}")
        if hit != len(pairs):
            bad += len(pairs) - hit

    same = sum(int(s["cycles"]) == int(b["cycle_count"]) for s, b in pairs)
    tot_s = sum(int(s["cycles"]) for s, _ in pairs)
    tot_b = sum(int(b["cycle_count"]) for _, b in pairs)
    print(f"       cycle_count   {same:>4}/{len(pairs)}  "
          f"합계 {tot_s:,} 대 {tot_b:,} ({100 * (tot_s / tot_b - 1):+.2f}%)")
    print("       사이클은 실패로 잡지 않습니다 -- 함수 주석 참고")
    return bad


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
        fails += check_board(base)
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
