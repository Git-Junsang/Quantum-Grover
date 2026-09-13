#!/usr/bin/env python3
"""
500 워크로드 벤치 결과를 집계하고, 같은 500 워크로드를 쓴 두 근거와 맞댑니다.

    bench500_report.py <csv>                 집계 + 6단계 대조 + 보드 대조
    bench500_report.py <base.csv> <cmp.csv>  두 갈래 교차 검증까지

맞대는 상대가 둘입니다. 셋 다 워크로드가 같습니다 (M = 1/4/16/64/256 x 시드 100).

  1. 6단계 ablation 캠페인의 K3/H3-E4-M2 단계 -- RTL 사이클 축.
     iverilog 로 돌았습니다. 그 공통소스의 Main IP 가 지금 src/ 의 Main IP 이고
     (MEAS_M1/M2 스위치, 기본 1 = 보드 구성), 캠페인 재현은 태그
     board-k3h3-e4-m2 에서 make anchor · make publication 으로 합니다
  2. 2026-09-08 보드 500런의 M2 경로 -- 보드 실경과 시간 축.
     같은 코어를 Arty A7 에 구워 돌린 것입니다

논리 궤적 넷(result_index·trial_count·L_BBHT·actual_iter)은 셋이 전부 같아야
합니다. 사이클은 세어서 보여만 주고 실패로 잡지 않습니다 -- 시뮬레이터와
실행 맥락이 달라 몇 건이 어긋나는 것이 이미 알려져 있습니다
(results/2026-09-10_bench250_final_core/evidence.md 참고).

**Normal 모드 사이클을 6단계의 Normal-E1 과 맞대면 안 됩니다.** 지금 src/ 는
INTRA_ENGINES=4 로 컴파일돼 있어서 mode0 도 E4 입니다. Normal-E1 은
INTRA_ENGINES=1 빌드의 mode0 이라 다른 물건입니다. 그래서 이 리포트는
K3/H3-E4-M2 단계(mode1)만 단계 대조에 씁니다.
"""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# 6단계 ablation 캠페인. 워크로드별 관측 3,000개 중 마지막 단계만 씁니다.
PUB_OBS = os.path.join(HERE, os.pardir, "results",
                       "2026-09-08_publication_6stage", "observations.csv")
PUB_STAGE = "K3/H3-E4-M2"

# 보드 500런의 M2 경로.
BOARD_M2 = os.path.join(HERE, os.pardir, "vivado", "vivado_bbht_grover_fpga",
                        "2026-09-08_k3h3_e4_m2_board_500run", "per_run_m2.csv")

# 250쌍 벤치가 이미 낸 근거. 앞 50 시드가 겹치므로 부분집합 대조를 합니다.
BENCH250 = os.path.join(HERE, os.pardir, "results",
                        "2026-09-10_bench250_final_core", "per_workload.csv")

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
    print(f"  워크로드        {len(rows) // 2:>12,} (모드당)")
    print(f"  총 샷           {n['trial']:>12,}")
    print(f"  Normal 반복     {n['iter']:>12,}   사이클 {n['cycles']:>12,}")
    print(f"  체크포인트 반복 {k['iter']:>12,}   사이클 {k['cycles']:>12,}")
    print(f"  반복 감소 {100 * (1 - k['iter'] / n['iter']):.2f}%"
          f"   사이클 감소 {100 * (1 - k['cycles'] / n['cycles']):.2f}%")
    print(f"  policy stall    {k['policy_stall']:>12,}"
          f"  ({100 * k['policy_stall'] / k['cycles']:.2f}% of 체크포인트)")
    print(f"  plan_fifo_mismatch {k['mismatch']}  (0 이어야 합니다)")
    return n, k


def check_paired(name, rows):
    """체크포인트는 psi 를 어떻게 계산하느냐만 바꾸므로 궤적은 같아야 합니다."""
    total_k = sum(1 for k in rows if k[2] == "k4")
    bad = [k[:2] for k in rows
           if k[2] == "k4"
           and any(rows[k][f] != rows[(k[0], k[1], "normal")][f]
                   for f in ("trial", "l_bbht"))]
    mark = "ok  " if not bad else "FAIL"
    print(f"  {mark} [{os.path.basename(name)}] Normal vs 체크포인트 궤적  "
          f"{total_k - len(bad)}/{total_k} 일치"
          + (f"  어긋난 곳 {bad[:5]}" if bad else ""))
    return len(bad)


def compare(title, rows, ref, mapping, cyc_field, note=""):
    """워크로드별로 맞댑니다. 논리 넷은 실패로 잡고 사이클은 보여만 줍니다."""
    pairs = [(rows[k], ref[(k[0], k[1])]) for k in sorted(rows)
             if k[2] == "k4" and (k[0], k[1]) in ref]
    print(f"\n=== {title} ===")
    if not pairs:
        print("  겹치는 워크로드가 없습니다")
        return 0, pairs

    bad = 0
    for label, ours, theirs in mapping:
        hit = sum(s[ours] == b[theirs] for s, b in pairs)
        mark = "ok  " if hit == len(pairs) else "FAIL"
        print(f"  {mark} {label:<14}{hit:>4}/{len(pairs)}")
        if hit != len(pairs):
            bad += len(pairs) - hit

    same = sum(int(s["cycles"]) == int(b[cyc_field]) for s, b in pairs)
    tot_s = sum(int(s["cycles"]) for s, _ in pairs)
    tot_b = sum(int(b[cyc_field]) for _, b in pairs)
    print(f"       cycle_count   {same:>4}/{len(pairs)}  "
          f"합계 {tot_s:,} 대 {tot_b:,} ({100 * (tot_s / tot_b - 1):+.2f}%)")
    if note:
        print(f"       {note}")
    return bad, pairs


def by_target(pairs, cyc_field, ref_label):
    """타겟수별로 쪼갠 사이클 표. 희소할수록 이득이 크다는 주장을 여기서 봅니다."""
    buckets = {}
    for s, b in pairs:
        buckets.setdefault(int(s["m"]), []).append((int(s["cycles"]),
                                                    int(b[cyc_field])))
    print(f"\n  타겟수별 사이클 (우리 벤치 대 {ref_label})")
    print(f"    {'M':>4} {'n':>5} {'벤치':>14} {'상대':>14} {'차이':>9} {'일치':>8}")
    for m in sorted(buckets):
        vals = buckets[m]
        ours = sum(a for a, _ in vals)
        ref = sum(b for _, b in vals)
        hit = sum(a == b for a, b in vals)
        print(f"    {m:>4} {len(vals):>5} {ours:>14,} {ref:>14,} "
              f"{100 * (ours / ref - 1):>+8.2f}% {hit:>4}/{len(vals)}")


def load_pub():
    path = os.path.normpath(PUB_OBS)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return {(int(r["target_count"]), int(r["seed_index"])): r
                for r in csv.DictReader(handle) if r["stage"] == PUB_STAGE}


def load_board():
    path = os.path.normpath(BOARD_M2)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return {(int(r["target_count"]), int(r["seed_index"])): r
                for r in csv.DictReader(handle)}


def check_bench250(rows):
    """앞 50 시드 250개가 250쌍 벤치와 같은지.

    같은 하네스·같은 자극이고 실행 길이만 다릅니다 (250개를 도느냐 500개 중
    앞부분이냐). 논리 궤적은 반드시 같아야 하고, 사이클이 어긋난다면 그것이
    바로 "연달아 도는 길이가 사이클에 영향을 준다" 는 증거입니다.
    """
    path = os.path.normpath(BENCH250)
    if not os.path.exists(path):
        return 0
    old = load(path)
    keys = [k for k in sorted(rows) if k[2] == "k4" and k[1] < 50 and k in old]
    print(f"\n=== 250쌍 벤치와의 부분집합 대조 (앞 50 시드) ===")
    if not keys:
        print("  겹치는 워크로드가 없습니다")
        return 0
    bad = 0
    for label, field in (("result_index", "result_index"), ("trial_count", "trial"),
                         ("L_BBHT", "l_bbht"), ("actual_iter", "iter")):
        hit = sum(rows[k][field] == old[k][field] for k in keys)
        mark = "ok  " if hit == len(keys) else "FAIL"
        print(f"  {mark} {label:<14}{hit:>4}/{len(keys)}")
        if hit != len(keys):
            bad += len(keys) - hit
    same = sum(int(rows[k]["cycles"]) == int(old[k]["cycles"]) for k in keys)
    tot_n = sum(int(rows[k]["cycles"]) for k in keys)
    tot_o = sum(int(old[k]["cycles"]) for k in keys)
    print(f"       cycle_count   {same:>4}/{len(keys)}  "
          f"합계 {tot_n:,} 대 {tot_o:,} ({100 * (tot_n / tot_o - 1):+.2f}%)")
    print("       사이클이 어긋나면 연달아 도는 길이가 영향을 준다는 뜻입니다")
    return bad


def check_cross(base, cmp_):
    fails = 0
    for mode in ("normal", "k4"):
        keys = [k for k in base if k[2] == mode]
        bad = [k[:2] for k in keys
               if any(base[k][f] != cmp_[k][f] for f in FIELDS)]
        mark = "ok  " if not bad else "FAIL"
        print(f"  {mark} [{mode}] 두 갈래 궤적  {len(keys) - len(bad)}/{len(keys)} 일치"
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

    pub = load_pub()
    if pub is None:
        print(f"\n=== 6단계 대조 === 건너뜀 (없음: {PUB_OBS})")
    else:
        bad, pairs = compare(
            f"6단계 ablation 대조 ({PUB_STAGE}, RTL 사이클 축, iverilog)",
            base, pub,
            (("result_index", "result_index", "result_index"),
             ("trial_count", "trial", "trial_count"),
             ("L_BBHT", "l_bbht", "L_BBHT"),
             ("actual_iter", "iter", "actual_iter")),
            "cycles",
            "캠페인 확정값 6,890,470 사이클 (Normal-E1 대비 6.1401x)")
        fails += bad
        by_target(pairs, "cycles", "6단계 M2")

    board = load_board()
    if board is None:
        print(f"\n=== 보드 실측 대조 === 건너뜀 (없음: {BOARD_M2})")
    else:
        bad, pairs = compare(
            "보드 실측 대조 (2026-09-08 M2, 같은 코어, 보드 실경과 시간 축)",
            base, board,
            (("result_index", "result_index", "result_index"),
             ("trial_count", "trial", "trial_count"),
             ("L_BBHT", "l_bbht", "l_bbht"),
             ("actual_iter", "iter", "actual_iter")),
            "cycle_count",
            "보드 사이클과 RTL 사이클로 배수를 만들지 마십시오")
        fails += bad
        by_target(pairs, "cycle_count", "보드 M2")

    fails += check_bench250(base)

    if len(sys.argv) == 3:
        cmp_ = load(sys.argv[2])
        report(sys.argv[2], cmp_)
        print("\n=== 두 갈래 교차 검증 ===")
        fails += check_paired(sys.argv[2], cmp_)
        fails += check_cross(base, cmp_)

    print("\n통과" if fails == 0 else f"\n실패 {fails}건")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
