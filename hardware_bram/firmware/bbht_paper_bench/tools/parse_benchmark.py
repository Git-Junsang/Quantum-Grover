#!/usr/bin/env python3
"""
보드 벤치 UART 로그를 표로 바꿉니다.

    python3 parse_benchmark.py uart.log

옆에 두 파일을 만듭니다.

    uart.raw.csv       실행 한 줄에 한 행. 보드 실측 묶음의 per_run_*.csv 와
                       같은 열 구성입니다
    uart.summary.csv   타겟 수 × 모드별 집계. 같은 묶음의 summary.csv 와
                       같은 열 구성입니다

펌웨어(`src/main.c`)는 워크로드마다 두 줄을 찍습니다 -- mode=0 이 Normal,
mode=1 이 최적화 경로입니다. 시간은 RVX 실시간 클럭 틱(마이크로초)이고
`timer_hi`·`timer_lo` 두 워드로 나옵니다. 측정 구간은 명령을 넣은 순간부터
DONE 을 본 순간까지이며, 설정·DMA·결과 읽기·printf 는 빠져 있습니다.

비교 대상은 `hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/`
입니다. 같은 펌웨어가 낸 로그라 열이 그대로 맞습니다.
"""
import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

# 펌웨어가 찍는 HW_REALTIME_CSV 줄의 필드 순서입니다. 헤더 줄
# (HW_REALTIME_CSV_HEADER) 이 로그 앞머리에 같은 순서로 들어 있습니다.
FIELDS = [
    "target_count", "seed_index", "seed_j", "seed_meas", "mode",
    "success", "result_valid", "result_index", "trial_count", "l_bbht",
    "actual_iter", "cycle_count", "timer_hi", "timer_lo", "status",
    "timeout", "unexpected_error", "terminal_limit",
]

# 16진수로 찍히는 것들. 나머지는 10진수 정수입니다.
HEX_FIELDS = {"seed_j", "seed_meas", "status"}

MODE_NAME = {0: "Normal_mode0", 1: "Optimized_mode1"}


def parse_rows(log):
    rows = []
    for raw in log.read_text(errors="ignore").splitlines():
        line = raw.strip()
        # UART 로그 앞에 "# " 가 붙어 오는 경우가 있습니다.
        if line.startswith("# "):
            line = line[2:]
        if not line.startswith("HW_REALTIME_CSV,"):
            continue
        parts = next(csv.reader([line]))[1:]
        if len(parts) != len(FIELDS):
            print("열 개수가 %d 개입니다 (기대 %d): %s"
                  % (len(parts), len(FIELDS), line[:60]), file=sys.stderr)
            continue
        row = {}
        for name, text in zip(FIELDS, parts):
            row[name] = text if name in HEX_FIELDS else int(text)
        # 보드 실측 CSV 와 같은 자리에 경과 시간을 붙입니다.
        row["elapsed_us"] = (row["timer_hi"] << 32) | row["timer_lo"]
        rows.append(row)
    return rows


def percentile95(values):
    """summary.csv 와 같은 방식. 오름차순에서 위쪽 5% 경계 표본을 고릅니다."""
    if not values:
        return 0
    ordered = sorted(values)
    idx = int(round(0.95 * (len(ordered) - 1)))
    return ordered[idx]


def summarize(rows):
    grouped = defaultdict(list)
    for r in rows:
        grouped[(r["mode"], r["target_count"])].append(r)
        grouped[(r["mode"], "ALL")].append(r)

    out = []
    for mode in sorted({m for m, _ in grouped}):
        keys = [t for m, t in grouped if m == mode and t != "ALL"]
        for target in sorted(keys) + ["ALL"]:
            group = grouped[(mode, target)]
            us = [r["elapsed_us"] for r in group]
            cyc = [r["cycle_count"] for r in group]
            out.append({
                "configuration": MODE_NAME.get(mode, "mode%d" % mode),
                "target_count": target,
                "runs": len(group),
                "success": sum(r["success"] for r in group),
                "sum_us": sum(us),
                "mean_us": sum(us) / len(us),
                "median_us": statistics.median(us),
                "p95_us": percentile95(us),
                "min_us": min(us),
                "max_us": max(us),
                "sum_cycles": sum(cyc),
                "mean_cycles": sum(cyc) / len(cyc),
                "median_cycles": statistics.median(cyc),
            })
    return out


def main():
    if len(sys.argv) != 2:
        print("사용법: parse_benchmark.py <uart_log.txt>")
        raise SystemExit(2)

    log = Path(sys.argv[1])
    rows = parse_rows(log)
    if not rows:
        print("HW_REALTIME_CSV 줄을 못 찾았습니다. 옛 펌웨어(RUN, 줄)의 로그라면 "
              "펌웨어를 실시간판으로 올린 뒤 다시 재십시오.")
        raise SystemExit(1)

    raw_csv = log.with_suffix(".raw.csv")
    with raw_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS + ["elapsed_us"])
        w.writeheader()
        w.writerows(rows)

    summary = summarize(rows)
    summary_csv = log.with_suffix(".summary.csv")
    with summary_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(summary[0]))
        w.writeheader()
        w.writerows(summary)

    print(raw_csv)
    print(summary_csv)

    # 모드별 전체 합만 화면에 보여 줍니다. 짝 비교는 표를 열어서 하십시오.
    total = {r["configuration"]: r for r in summary if r["target_count"] == "ALL"}
    base = total.get("Normal_mode0")
    for name, r in total.items():
        line = ("%-16s runs=%3d 성공=%3d 합=%9d us 중앙값=%8.1f us"
                % (name, r["runs"], r["success"], r["sum_us"], r["median_us"]))
        if base and r is not base and r["sum_us"]:
            line += "  Normal 대비 %.3fx" % (base["sum_us"] / r["sum_us"])
        print(line)


if __name__ == "__main__":
    main()
