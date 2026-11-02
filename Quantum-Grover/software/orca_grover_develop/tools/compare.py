#!/usr/bin/env python3
"""
ORCA 보드 · 서버 · FPGA 보드의 Predicate500 결과를 워크로드마다 맞대고 합계를 냅니다.

    compare.py --fpga <FPGA predicate500.csv> --out <폴더>
               --orca-normal <uart.log> --orca-k3h3 <uart.log>
               --orca-naive-calib <uart.log> --orca-naive-subset <uart.log>
               --host-normal <log>... --host-k3h3 <log>... --host-naive <log> --host-naive-calib <log>...

입력
  ORCA 로그   보드 UART 캡처. SW_RUN 줄의 timer_hi/lo 가 bbht_search() 구간 us (RVX 실시간 클럭 1 MHz).
              ORCA 는 50 MHz 이므로 사이클 = us x 50 (환산값).
  서버 로그   같은 소스를 서버에서 빌드한 실행 출력. SW_RUN 의 timer 는 CLOCK_MONOTONIC_RAW us,
              HOST_CYCLES 줄은 같은 구간의 사용자 공간 코어 사이클(perf_event, 실측).
              ③ · ② 는 여러 번 돌린 로그를 받아 워크로드마다 중앙값을 씁니다.
  FPGA CSV    software/host_fpga_develop/bbht_predicate500.py 가 낸 표. normal 은 ③ · ①, ckpt 는 ② 와 짝입니다.
              wall_us 는 보드 실시간 클럭(1 MHz)으로 COMMAND 직전 ~ DONE, cycle_count 는 가속기 100 MHz 사이클.

① naive 는 ORCA 에서 2,000개를 끝까지 돌릴 수 없어(약 4.6년) CALIBRATE 단가로 추정합니다.
    추정 = 반복 수 x 반복 1회 시간 + 시도 수 x 측정 1회 시간
SUBSET 실측과 서버 ① FULL 로 이 식을 확인한 결과를 validation.txt 에 적습니다.

출력: per_run.csv · summary.csv · host_repeats.csv · validation.txt
"""
import argparse
import csv
import statistics
from collections import defaultdict
from pathlib import Path

PRED = ["LT", "GT", "EQ", "RANGE"]
MS = [1, 4, 16, 64, 256]
TRAJ = ["seed_j", "seed_meas", "success", "result_index", "trial_count", "L_BBHT", "actual_iter",
        "termination", "saturations"]


def read_log(path):
    """SW_RUN 줄과 HOST_CYCLES 줄을 읽어 워크로드 키 -> 행 사전으로 돌려줍니다."""
    runs, cycles, calib, bad = [], {}, {}, 0
    for raw in Path(path).read_text(errors="replace").splitlines():
        f = raw.strip("\r").split(",")
        if f[0] == "SW_RUN":
            if len(f) != 16:
                bad += 1
                continue
            runs.append(dict(model=int(f[1]), predicate=f[2], target_count=int(f[3]), seed_index=int(f[4]),
                             seed_j=f[5].lower(), seed_meas=f[6].lower(), success=int(f[7]),
                             result_index=int(f[8]), trial_count=int(f[9]), L_BBHT=int(f[10]),
                             actual_iter=int(f[11]), termination=int(f[12]), saturations=int(f[13]),
                             us=(int(f[14]) << 32) + int(f[15])))
        elif f[0] == "HOST_CYCLES":
            cycles[int(f[1])] = int(f[2])
        elif f[0] in ("SW_CALIB_ITER", "SW_CALIB_MEASURE"):
            n = int(f[2].split("=")[1])
            calib[f[0]] = ((int(f[3]) << 32) + int(f[4])) / n
    # HOST_CYCLES 순번은 SW_RUN 줄 순서와 같습니다 (CALIBRATE 는 반복 · 측정 두 쌍).
    for i, r in enumerate(runs):
        r["cycles"] = cycles.get(i)
    if calib and cycles:
        calib["cycles_iter"] = cycles.get(0)
        calib["cycles_measure"] = cycles.get(1)
    out = {}
    for r in runs:
        out[(r["predicate"], r["target_count"], r["seed_index"])] = r
    return out, len(runs), bad, calib


def read_fpga(path):
    out = {}
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            k = (r["predicate"], int(r["target_count"]), int(r["seed_index"]))
            out.setdefault(k, {})[r["mode"]] = r
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fpga", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--orca-normal", required=True)
    ap.add_argument("--orca-k3h3", required=True)
    ap.add_argument("--orca-naive-calib", required=True)
    ap.add_argument("--orca-naive-subset", required=True)
    ap.add_argument("--host-normal", nargs="+", required=True)
    ap.add_argument("--host-k3h3", nargs="+", required=True)
    ap.add_argument("--host-naive", required=True)
    ap.add_argument("--host-naive-calib", nargs="+", required=True)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    v = []   # validation.txt 줄

    fpga = read_fpga(a.fpga)
    keys = [(p, m, s) for p in PRED for m in MS for s in range(100)]
    v.append(f"fpga {a.fpga}")
    v.append(f"fpga workloads {len(fpga)} (normal+ckpt per key: "
             f"{sum(1 for k in keys if set(fpga.get(k, {})) >= {'normal', 'ckpt'})})")

    def load(label, path, model):
        rows, n, bad, _ = read_log(path)
        dup = n - len(rows)
        miss = sum(1 for k in keys if k not in rows)
        wrong = sum(1 for r in rows.values() if r["model"] != model)
        v.append(f"{label}: {path}")
        v.append(f"  rows {n} format_errors {bad} duplicates {dup} missing {miss} wrong_model {wrong}")
        return rows

    orca_n = load("orca ③ normal", a.orca_normal, 3)
    orca_k = load("orca ② k3h3", a.orca_k3h3, 2)
    host_n_runs = [load(f"host ③ normal #{i + 1}", p, 3) for i, p in enumerate(a.host_normal)]
    host_k_runs = [load(f"host ② k3h3 #{i + 1}", p, 2) for i, p in enumerate(a.host_k3h3)]
    host_naive = load("host ① naive", a.host_naive, 1)

    # 궤적: 모든 실행이 FPGA 와 같은가 (시간 열은 빼고)
    def traj_vs_fpga(rows, mode):
        mism = defaultdict(int)
        for k in keys:
            r, f = rows.get(k), fpga.get(k, {}).get(mode)
            if r is None or f is None:
                mism["missing"] += 1
                continue
            fv = dict(seed_j=f["seed_j"].lower(), seed_meas=f["seed_meas"].lower(),
                      result_index=int(f["result_index"]), trial_count=int(f["trial_count"]),
                      L_BBHT=int(f["L_BBHT"]), actual_iter=int(f["actual_iter"]))
            for c, val in fv.items():
                if r[c] != val:
                    mism[c] += 1
            if not r["success"]:
                mism["not_success"] += 1
        return dict(mism)

    v.append("trajectory vs FPGA (seed_j seed_meas result_index trial_count L_BBHT actual_iter; 0 = all equal)")
    for label, rows, mode in [("orca ③", orca_n, "normal"), ("orca ②", orca_k, "ckpt"),
                              ("host ① ", host_naive, "normal")] + \
            [(f"host ③ #{i + 1}", r, "normal") for i, r in enumerate(host_n_runs)] + \
            [(f"host ② #{i + 1}", r, "ckpt") for i, r in enumerate(host_k_runs)]:
        m = traj_vs_fpga(rows, mode)
        v.append(f"  {label:12s} {'0 mismatches' if not m else m}")

    # 같은 모델끼리는 플랫폼이 달라도 시간 열을 뺀 모든 열이 같아야 합니다.
    def same_cols(r1, r2):
        return sum(1 for k in keys if any(r1[k][c] != r2[k][c] for c in TRAJ))
    v.append("cross-platform, all non-time columns incl. termination and saturations")
    v.append(f"  orca ③ vs host ③ #1: {same_cols(orca_n, host_n_runs[0])} differing workloads")
    v.append(f"  orca ② vs host ② #1: {same_cols(orca_k, host_k_runs[0])} differing workloads")
    v.append(f"  host ① vs orca ③   : {same_cols(host_naive, orca_n)} differing workloads (naive = Normal 궤적)")
    for i, r in enumerate(host_n_runs[1:], 2):
        v.append(f"  host ③ #1 vs #{i}: {same_cols(host_n_runs[0], r)}")
    for i, r in enumerate(host_k_runs[1:], 2):
        v.append(f"  host ② #1 vs #{i}: {same_cols(host_k_runs[0], r)}")

    # ① naive 단가 (ORCA, 서버)
    _, _, _, oc = read_log(a.orca_naive_calib)
    o_it, o_me = oc["SW_CALIB_ITER"], oc["SW_CALIB_MEASURE"]
    hc = [read_log(p)[3] for p in a.host_naive_calib]
    h_it = statistics.median(c["SW_CALIB_ITER"] for c in hc)
    h_me = statistics.median(c["SW_CALIB_MEASURE"] for c in hc)
    v.append(f"naive unit cost: orca iter {o_it:.1f} us, measure {o_me:.1f} us; "
             f"host iter {h_it:.1f} us, measure {h_me:.1f} us (median of {len(hc)})")
    sub, _, _, _ = read_log(a.orca_naive_subset)
    v.append("orca ① SUBSET: estimate = L x iter + trials x measure vs measured")
    for k, r in sorted(sub.items()):
        est = r["L_BBHT"] * o_it + r["trial_count"] * o_me
        f = fpga.get(k, {}).get("normal")
        ok = f is not None and all(r[c] == int(f[c]) for c in ("result_index", "trial_count", "L_BBHT"))
        v.append(f"  {k}: L={r['L_BBHT']} trials={r['trial_count']} measured={r['us']} est={est:.0f} "
                 f"diff={(r['us'] - est) / est * 100:+.4f}%  fpga_trajectory={'same' if ok else 'DIFF'}")
    h_tot = sum(r["us"] for r in host_naive.values())
    h_est = sum(r["L_BBHT"] * h_it + r["trial_count"] * h_me for r in host_naive.values())
    v.append(f"host ① FULL: measured {h_tot} us vs estimate {h_est:.0f} us ({(h_tot - h_est) / h_est * 100:+.2f}%)")

    # per_run.csv
    def med(runs, k, col):
        vals = [r[k][col] for r in runs]
        return int(statistics.median(vals)) if None not in vals else ""
    per = []
    for k in keys:
        n, c, f = orca_n[k], orca_k[k], fpga[k]
        per.append(dict(
            predicate=k[0], target_count=k[1], seed_index=k[2], seed_j=n["seed_j"], seed_meas=n["seed_meas"],
            result_index=n["result_index"], trial_count=n["trial_count"], L_BBHT=n["L_BBHT"],
            iter_normal=n["actual_iter"], iter_k3h3=c["actual_iter"],
            orca_normal_us=n["us"], orca_k3h3_us=c["us"],
            orca_naive_est_us=round(n["L_BBHT"] * o_it + n["trial_count"] * o_me),
            host_normal_us=med(host_n_runs, k, "us"), host_normal_cycles=med(host_n_runs, k, "cycles"),
            host_k3h3_us=med(host_k_runs, k, "us"), host_k3h3_cycles=med(host_k_runs, k, "cycles"),
            host_naive_us=host_naive[k]["us"], host_naive_cycles=host_naive[k]["cycles"],
            fpga_normal_wall_us=int(f["normal"]["wall_us"]), fpga_normal_cycles=int(f["normal"]["cycle_count"]),
            fpga_ckpt_wall_us=int(f["ckpt"]["wall_us"]), fpga_ckpt_cycles=int(f["ckpt"]["cycle_count"])))
    with open(out / "per_run.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(per[0].keys()))
        w.writeheader()
        w.writerows(per)

    # host_repeats.csv: 반복마다 합계
    with open(out / "host_repeats.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["model", "repeat", "total_us", "total_cycles"])
        for name, runs in (("normal", host_n_runs), ("k3h3", host_k_runs)):
            for i, r in enumerate(runs, 1):
                w.writerow([name, i, sum(x["us"] for x in r.values()), sum(x["cycles"] for x in r.values())])

    # summary.csv: 시스템 x 모델 x 묶음(전체, M 별)
    systems = [
        # 이름, 모델, 실측/추정, 클럭(Hz), 시간 열, 사이클 열(없으면 시간 x 클럭), 실제 반복 열, 사이클 출처
        ("ORCA", "③ normal", "measured", 50_000_000, "orca_normal_us", None, "iter_normal", "us x 50 (환산)"),
        ("ORCA", "② k3h3", "measured", 50_000_000, "orca_k3h3_us", None, "iter_k3h3", "us x 50 (환산)"),
        ("ORCA", "① naive", "estimated", 50_000_000, "orca_naive_est_us", None, "iter_normal", "us x 50 (환산)"),
        ("host", "③ normal", "measured (median of runs)", "", "host_normal_us", "host_normal_cycles", "iter_normal",
         "perf 코어 사이클 (실측)"),
        ("host", "② k3h3", "measured (median of runs)", "", "host_k3h3_us", "host_k3h3_cycles", "iter_k3h3",
         "perf 코어 사이클 (실측)"),
        ("host", "① naive", "measured", "", "host_naive_us", "host_naive_cycles", "iter_normal",
         "perf 코어 사이클 (실측)"),
        ("FPGA M2", "normal", "measured", 100_000_000, "fpga_normal_wall_us", "fpga_normal_cycles", "iter_normal",
         "가속기 cycle_count (100 MHz)"),
        ("FPGA M2", "ckpt", "measured", 100_000_000, "fpga_ckpt_wall_us", "fpga_ckpt_cycles", "iter_k3h3",
         "가속기 cycle_count (100 MHz)"),
    ]
    groups = [("all", lambda r: True)] + [(f"M={m}", (lambda m: lambda r: r["target_count"] == m)(m)) for m in MS]
    with open(out / "summary.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["system", "model", "kind", "clock_hz", "group", "runs", "trials", "L_BBHT", "actual_iter",
                    "time_us", "cycles", "cycles_source"])
        for sysname, model, kind, clk, tcol, ccol, icol, csrc in systems:
            for g, sel in groups:
                rs = [r for r in per if sel(r)]
                t = sum(r[tcol] for r in rs)
                cyc = sum(r[ccol] for r in rs) if ccol else t * clk // 1_000_000
                w.writerow([sysname, model, kind, clk, g, len(rs), sum(r["trial_count"] for r in rs),
                            sum(r["L_BBHT"] for r in rs), sum(r[icol] for r in rs), t, cyc, csrc])
    (out / "validation.txt").write_text("\n".join(v) + "\n")
    print("\n".join(v))


if __name__ == "__main__":
    main()
