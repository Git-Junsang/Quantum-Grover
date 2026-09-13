#!/usr/bin/env python3
"""
500 워크로드 벤치 3자 대조. bench250_report.py 와 같은 논리를 시드 100쌍
(M = 1/4/16/64/256 x 시드 100 = 500) 에 적용합니다.

    python3 bench500_report.py <dram.csv> <bram.csv>

<bram.csv> 는 mode 열에 normal/ckpt 가 섞인 1,000행짜리 파일이고,
<dram.csv> 는 mode=dram 인 500행짜리 파일입니다 (tb_dram_bench500.v 가
그렇게 냅니다).

500 으로 올린 이유는 표본을 정본 근거와 맞추기 위해서입니다. 보드 실측과
6단계 ablation 이 전부 이 500 워크로드를 쓰므로, 여기서 나온 dram 대
K3/H3-E4-M2 비교를 그 근거들과 같은 자리에 놓을 수 있습니다.

불변식 (반드시 같아야 하는 것)
    trial, l_bbht, result_index -- 이 셋이 세 갈래에서 같다는 것이
    "DRAM 갈래가 보드 검증 정본과 같은 계산을 한다" 의 근거입니다.
    체크포인트/DRAM 은 psi 를 어떻게 다시 만드느냐만 바꾸므로, 진폭이
    한 비트라도 어긋나면 이 셋이 즉시 갈라집니다.

비용 (갈라져야 정상인 것)
    iter, cycles. M(정답 개수)별, 그리고 500개 전체로 짝지어(paired)
    승/무/패 를 셉니다.

여기 사이클은 통신 계층 없이 Main IP 포트를 직접 흔든 값입니다. 그런데도
bram 코어를 물린 쪽(normal/ckpt)이 hardware_bram/sim/bench500 의 드라이버
하네스와도, 2026-09-08 보드 M2 실측과도 500/500 사이클이 같습니다 --
CSR_CYCLE_COUNT 의 계측 구간이 탐색 자체라 통신 계층이 끼든 안 끼든
바뀌지 않기 때문입니다. 그래서 이 표의 dram 대 ckpt 비교는 보드 실측과
같은 사이클 축 위에 있습니다.

다만 dram 쪽 사이클은 동작 수준 DRAM 모델 위의 값입니다. 지연을 어떻게
주느냐(WR_LAT/RD_LAT/BEAT_GAP/STALL_EN)에 따라 달라지므로, 어떤 지연으로
쟀는지를 반드시 같이 인용하십시오. 물리 MIG 바인딩은 아직 없습니다.
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


def seed_count(rows):
    """시드 수를 데이터에서 읽습니다. TB 의 NSEED 를 여기 박아 두지 않습니다."""
    return max(k[1] for k in rows) + 1


def check_trajectory(dram, bram, nseed):
    """세 갈래 모두 같은 (m, seed) 에서 같은 trial/l_bbht/idx 를 내는가."""
    bad = []
    for m in M_VALUES:
        for s in range(nseed):
            d = dram.get((m, s, "dram"))
            n = bram.get((m, s, "normal"))
            k = bram.get((m, s, "ckpt"))
            if d is None or n is None or k is None:
                bad.append((m, s, "누락"))
                continue
            for f in TRAJ_FIELDS:
                if not (d[f] == n[f] == k[f]):
                    bad.append((m, s, "%s: dram=%s normal=%s ckpt=%s"
                                % (f, d[f], n[f], k[f])))
                    break
    return bad


def cfgerr_check(rows, name):
    bad = [k for k, r in rows.items() if r["cfgerr"] != "0"]
    if bad:
        print("  FAIL [%s] config_error 가 뜬 케이스 %d 건 (0 이어야 합니다): %s"
              % (name, len(bad), bad[:5]))
    return len(bad)


def paired_stats(label, dram, other, other_mode, nseed):
    """dram 대 other_mode 를 짝지어 비교."""
    total = len(M_VALUES) * nseed
    print("\n=== %s: dram vs %s ===" % (label, other_mode))
    header = ("%-6s %6s %14s %14s %10s %10s %10s %10s" %
              ("M", "쌍수", "dram 반복합", "%s 반복합" % other_mode,
               "dram<", "동률", "dram>", "반복비"))
    print(header)
    print("-" * len(header))

    grand = {}
    for m in list(M_VALUES) + [None]:
        keys = [(m, s) for s in range(nseed)] if m is not None else \
               [(mm, s) for mm in M_VALUES for s in range(nseed)]
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
            grand = dict(di=di, oi=oi, dc=dc, oc=oc, win=win, tie=tie, lose=lose)

    print()
    cyc_pct = 100.0 * (grand["dc"] - grand["oc"]) / grand["oc"] if grand["oc"] else float("nan")
    iter_pct = 100.0 * (grand["di"] - grand["oi"]) / grand["oi"] if grand["oi"] else float("nan")
    print("  반복 합계: dram %d vs %s %d  (%+.2f%%)"
          % (grand["di"], other_mode, grand["oi"], iter_pct))
    print("  사이클 합계: dram %d vs %s %d  (%+.2f%%)"
          % (grand["dc"], other_mode, grand["oc"], cyc_pct))
    print("  사이클 기준 승/무/패 (%d쌍): dram 이 더 적음 %d / 동률 %d / dram 이 더 큼 %d"
          % (total, grand["win"], grand["tie"], grand["lose"]))
    return grand["dc"], grand["oc"]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    dram = load(sys.argv[1])
    bram = load(sys.argv[2])
    nseed = min(seed_count(dram), seed_count(bram))
    total = len(M_VALUES) * nseed

    print("=" * 78)
    print("궤적 대조 (%d쌍 x 3갈래) -- trial/l_bbht/result_index 가 전부 같아야 합니다"
          % total)
    print("=" * 78)
    bad = check_trajectory(dram, bram, nseed)
    if bad:
        print("FAIL 궤적이 갈라진 케이스 %d 건" % len(bad))
        for m, s, why in bad[:20]:
            print("  m=%d seed=%d  %s" % (m, s, why))
    else:
        print("ok   %d쌍 x 3갈래 전부 trial/l_bbht/result_index 일치" % total)

    errs = 0
    errs += cfgerr_check(dram, "dram")
    errs += cfgerr_check(bram, "bram")

    paired_stats("Normal 대비", dram, bram, "normal", nseed)
    paired_stats("K3/H3-E4-M2 대비", dram, bram, "ckpt", nseed)

    print()
    if bad or errs:
        print("결과: FAIL")
        return 1
    print("결과: PASS (궤적 일치, config_error 없음)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
