#!/usr/bin/env python3
"""
합성 리포트에서 자원 수치를 뽑아 기대값과 대조합니다.

두 가지 방식으로 씁니다.

    python3 parse_resource.py
        run_resource.sh 가 만든 work/<구성>/post_synth_util_hier.rpt 다섯 벌을
        읽어 u_main_ip 계층 사용량을 기대표와 대조합니다. 하나라도 어긋나면
        종료코드 1 입니다.

    python3 parse_resource.py --main-ip work_main_ip/util.rpt
        run_main_ip.sh 가 만든 OOC 리포트 하나를 읽어 최종 구성 기대값 옆에
        놓고 보여 줍니다. 조건이 달라 정확히 같지 않으므로 PASS/FAIL 을
        매기지 않고 차이만 적습니다.

기대값의 출처는 results/2026-09-08_resource_ablation_5config/main_ip_5config.csv
이고, 그 표는 Vivado 2024.2 공통조건 합성 결과입니다.
"""
import argparse
import csv
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORK = HERE / "work"

CONFIGS = ["k4h4_e1", "k4h4_e4", "k3h3_e4", "k3h3_e4_m1", "k3h3_e4_m2"]

# 구성 -> (LUT, FF, BRAM tile, DSP)
EXPECTED = {
    "k4h4_e1":    (13804, 13611, 66.0, 64),
    "k4h4_e4":    (30294, 25822, 83.0, 64),
    "k3h3_e4":    (29959, 25655, 83.0, 64),
    "k3h3_e4_m1": (33547, 28195, 84.0, 128),
    "k3h3_e4_m2": (33730, 28258, 84.0, 128),
}


def parse_hier(text):
    """계층 리포트에서 u_main_ip 줄을 뽑습니다.

    열 순서는 Vivado 가 내는 대로 total LUT / logic LUT / LUTRAM / SRL /
    FF / RAMB36 / RAMB18 / DSP 입니다. BRAM tile 은 RAMB36 + RAMB18/2 입니다.
    """
    m = re.search(r"^\|\s+u_main_ip\s+\|\s+bbht_grover_main_ip\s+\|"
                  + r"\s*(\d+)\s*\|" * 8, text, re.M)
    if not m:
        return None
    total, _logic, _lutram, _srl, ff, b36, b18, dsp = map(int, m.groups())
    return total, ff, b36 + b18 / 2, dsp


def parse_flat(text):
    """OOC 리포트의 요약 표에서 최상위 사용량을 뽑습니다.

    BRAM 은 `Block RAM Tile` 줄을 씁니다. 바로 아래 RAMB36/RAMB18 줄은
    그 tile 을 어떻게 쪼갰는지를 보여 주는 내역이라 따로 더하면 안 됩니다.
    """
    def cell(*labels):
        for label in labels:
            m = re.search(r"^\|\s*" + re.escape(label) + r"\s*\|\s*([0-9.]+)\s*\|",
                          text, re.M)
            if m:
                return float(m.group(1))
        return None

    lut = cell("Slice LUTs*", "Slice LUTs", "CLB LUTs")
    ff = cell("Slice Registers", "CLB Registers")
    tile = cell("Block RAM Tile")
    dsp = cell("DSPs", "DSP48E1 only")
    if tile is None:
        # 계층 리포트처럼 tile 줄이 없으면 RAMB36 + RAMB18/2 로 환산합니다.
        b36 = cell("RAMB36/FIFO*", "RAMB36/FIFO")
        b18 = cell("RAMB18") or 0.0
        tile = None if b36 is None else b36 + b18 / 2
    if None in (lut, ff, tile, dsp):
        return None
    return int(lut), int(ff), tile, int(dsp)


def report_five():
    rows = []
    ok = True
    for cfg in CONFIGS:
        path = WORK / cfg / "post_synth_util_hier.rpt"
        if not path.exists():
            print("리포트 없음: %s" % path)
            ok = False
            continue
        got = parse_hier(path.read_text(errors="replace"))
        if not got:
            print("파싱 실패: %s" % cfg)
            ok = False
            continue
        exp = EXPECTED[cfg]
        exact = (got == exp)
        ok &= exact
        print("%-12s LUT %6d FF %6d BRAM %5.1f DSP %3d   %s"
              % (cfg, got[0], got[1], got[2], got[3],
                 "일치" if exact else "기대 %s" % (exp,)))
        rows.append({
            "config": cfg,
            "LUT": got[0], "FF": got[1], "BRAM_tile": got[2], "DSP": got[3],
            "expected_LUT": exp[0], "expected_FF": exp[1],
            "expected_BRAM": exp[2], "expected_DSP": exp[3],
            "exact_match": int(exact),
        })

    if rows:
        out = WORK / "resource_main_ip_reproduced.csv"
        with out.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        print("기록: %s" % out)

    done = ok and len(rows) == len(CONFIGS)
    print("전체: %s" % ("일치" if done else "불일치"))
    return 0 if done else 1


def report_main_ip(path):
    text = Path(path).read_text(errors="replace")
    got = parse_flat(text)
    if not got:
        print("파싱 실패: %s" % path)
        return 1
    exp = EXPECTED["k3h3_e4_m2"]
    names = ["LUT", "FF", "BRAM tile", "DSP"]
    print("최종 구성 K3/H3-E4-M2 -- OOC 합성 대 공통조건 기대표")
    for name, g, e in zip(names, got, exp):
        diff = 100.0 * (g - e) / e if e else 0.0
        print("  %-10s %10s   기대 %10s   %+6.1f%%" % (name, g, e, diff))
    print("두 값은 조건이 다릅니다 (OOC 단독 대 standalone top 안의 계층). "
          "몇 % 차이는 정상입니다.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--main-ip", metavar="UTIL_RPT",
                    help="OOC 합성 리포트 하나를 기대값과 나란히 봅니다")
    args = ap.parse_args()
    return report_main_ip(args.main_ip) if args.main_ip else report_five()


if __name__ == "__main__":
    sys.exit(main())
