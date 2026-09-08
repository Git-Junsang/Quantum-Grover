#!/usr/bin/env python3
"""
250쌍 벤치 3자 대조. hardware_bram/sim/bench250_report.py 와 같은 논리를
dram/bram-Normal/bram-K4H4 세 갈래에 적용합니다.

    python3 bench250_report.py <dram.csv> <bram.csv>

<bram.csv> 는 mode 열에 normal/k4h4 가 섞인 500행짜리 파일이고, <dram.csv>
는 mode=dram 인 250행짜리 파일입니다 (tb_dram_bench250.v 가 그렇게 냅니다).

불변식 (반드시 같아야 하는 것)
    trial, l_bbht, result_index -- 이 셋이 세 갈래에서 같다는 것이
    "DRAM 갈래가 보드 검증 v0.9.8 과 같은 계산을 한다" 의 근거입니다.
    체크포인트/DRAM 은 psi 를 어떻게 다시 만드느냐만 바꾸므로, 진폭이
    한 비트라도 어긋나면 이 셋이 즉시 갈라집니다.

비용 (갈라져야 정상인 것)
    iter, cycles. M(정답 개수)별, 그리고 250개 전체로 짝지어(paired)
    승/무/패 를 셉니다 -- 2026-09-04 보드 실측(summary.csv)과 같은 통계.
"""
import csv
import sys

TRAJ_FIELDS = ("trial", "l_bbht", "result_index")
M_VALUES = (1, 4, 16, 64, 256)


def load(path):
    with open(path, encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(l for l in f if not l.startswith("#"))]
    out = {}
    for r in rows:
        out[(int(r["m"]), int(r["seed_idx"]), r["mode"])] = r
    return out


def check_trajectory(dram, bram):
    """세 갈래 모두 같은 (m, seed) 에서 같은 trial/l_bbht/idx 를 내는가."""
    bad = []
    for m in M_VALUES:
        for s in range(50):
            d = dram.get((m, s, "dram"))
            n = bram.get((m, s, "normal"))
            k = bram.get((m, s, "k4h4"))
            if d is None or n is None or k is None:
                bad.append((m, s, "누락"))
                continue
            for f in TRAJ_FIELDS:
                if not (d[f] == n[f] == k[f]):
                    bad.append((m, s, "%s: dram=%s normal=%s k4h4=%s"
                                % (f, d[f], n[f], k[f])))
                    break
    return bad


def cfgerr_check(rows, name):
    bad = [k for k, r in rows.items() if r["cfgerr"] != "0"]
    if bad:
        print("  FAIL [%s] config_error 가 뜬 케이스 %d 건 (0 이어야 합니다): %s"
              % (name, len(bad), bad[:5]))
    return len(bad)


def paired_stats(label, dram, other, other_mode):
    """dram 대 other_mode 를 250쌍 짝지어 비교. summary.csv 와 같은 지표."""
    print("\n=== %s: dram vs %s ===" % (label, other_mode))
    header = ("%-6s %6s %14s %14s %10s %10s %10s %10s" %
              ("M", "쌍수", "dram 반복합", "%s 반복합" % other_mode,
               "dram<", "동률", "dram>", "반복비"))
    print(header)
    print("-" * len(header))

    grand_di = grand_oi = grand_dc = grand_oc = 0
    grand_win = grand_tie = grand_lose = 0

    for m in list(M_VALUES) + [None]:
        keys = [(m, s) for s in range(50)] if m is not None else \
               [(mm, s) for mm in M_VALUES for s in range(50)]
        di = oi = dc = oc = 0
        win = tie = lose = 0
        for (mm, s) in keys:
            d = dram.get((mm, s, "dram"))
            o = other.get((mm, s, other_mode))
            if d is None or o is None:
                continue
            di += int(d["iter"]); oi += int(o["iter"])
            dc += int(d["cycles"]); oc += int(o["cycles"])
            if int(d["cycles"]) < int(o["cycles"]):
                win += 1
            elif int(d["cycles"]) > int(o["cycles"]):
                lose += 1
            else:
                tie += 1
        ratio = (oi / di) if di else float("nan")
        label_m = "ALL" if m is None else str(m)
        print("%-6s %6d %14d %14d %10d %10d %10d %9.2fx" %
              (label_m, len(keys), di, oi, win, tie, lose, ratio))
        if m is None:
            grand_di, grand_oi, grand_dc, grand_oc = di, oi, dc, oc
            grand_win, grand_tie, grand_lose = win, tie, lose

    print()
    cyc_pct = 100.0 * (grand_dc - grand_oc) / grand_oc if grand_oc else float("nan")
    iter_pct = 100.0 * (grand_di - grand_oi) / grand_oi if grand_oi else float("nan")
    print("  반복 합계: dram %d vs %s %d  (%+.2f%%)" % (grand_di, other_mode, grand_oi, iter_pct))
    print("  사이클 합계: dram %d vs %s %d  (%+.2f%%)" % (grand_dc, other_mode, grand_oc, cyc_pct))
    print("  사이클 기준 승/무/패 (250쌍): dram 이 더 적음 %d / 동률 %d / dram 이 더 큼 %d"
          % (grand_win, grand_tie, grand_lose))
    return grand_dc, grand_oc


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    dram = load(sys.argv[1])
    bram = load(sys.argv[2])

    print("=" * 78)
    print("궤적 대조 (250쌍 x 3갈래) -- trial/l_bbht/result_index 가 전부 같아야 합니다")
    print("=" * 78)
    bad = check_trajectory(dram, bram)
    if bad:
        print("FAIL 궤적이 갈라진 케이스 %d 건" % len(bad))
        for m, s, why in bad[:20]:
            print("  m=%d seed=%d  %s" % (m, s, why))
    else:
        print("ok   250쌍 x 3갈래 전부 trial/l_bbht/result_index 일치")

    errs = 0
    errs += cfgerr_check(dram, "dram")
    errs += cfgerr_check(bram, "bram")

    paired_stats("Normal 대비", dram, bram, "normal")
    paired_stats("K4/H4 대비", dram, bram, "k4h4")

    print()
    if bad or errs:
        print("결과: FAIL")
        return 1
    print("결과: PASS (궤적 일치, config_error 없음)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
