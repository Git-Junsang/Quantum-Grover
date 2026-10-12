"""verify_cpp_rtl_vs_golden_predicate500.py : C++ model B vs team golden expectations vs the 10/04 board runs (Predicate500).

Checks, per predicate and policy, result_index / trial_count / L_BBHT and the physical
iteration column that belongs to the policy:
  normal  -> actual_iter_normal      (bram NORMAL, nocheckpoint, board 'normal')
  k3h3    -> actual_iter_k3h3        (bram checkpoint, board 'ckpt')
  allj    -> actual_iter_dram_all_j  (DRAM table cleared per search)
  session -> actual_iter_dram_session (DRAM table kept across seeds; board DRAM 'normal')
"""
import argparse, csv
from collections import defaultdict
from pathlib import Path

from repo_paths import BOARD_P500_FILES, P500_EXPECTED

COL = {"normal": "actual_iter_normal", "k3h3": "actual_iter_k3h3",
       "allj": "actual_iter_dram_all_j", "session": "actual_iter_dram_session"}

ap = argparse.ArgumentParser()
ap.add_argument("--runs", required=True, help="dir with rtl_<PRED>_<policy>.csv")
ap.add_argument("--expected", default=str(P500_EXPECTED / "predicate500_expected.csv"))
ap.add_argument("--board", nargs="*", default=[str(p) for p in BOARD_P500_FILES], help="10/04 board result.csv files")
a = ap.parse_args()

exp = {(r["predicate"], int(r["target_count"]), int(r["seed_index"])): r for r in csv.DictReader(open(a.expected))}
cpp = defaultdict(dict)
ok_all = True
print("vs golden (predicate500_expected.csv):")
for pred in ("LT", "GT", "EQ", "RANGE"):
    line = []
    for pol, col in COL.items():
        rows = list(csv.DictReader(open(Path(a.runs) / f"rtl_{pred}_{pol}.csv")))
        good = 0
        for r in rows:
            k = (pred, int(r["target_count"]), int(r["seed_index"]))
            e = exp[k]
            cpp[pol][k] = r
            same = (r["result_index"], r["trial_count"], r["L_BBHT"], r["actual_grover_iterations"]) == \
                   (e["result_index"], e["trial_count"], e["L_BBHT"], e[col])
            good += same
        ok_all &= good == len(rows)
        line.append(f"{pol} {good}/{len(rows)}")
    print(f"  {pred:5s} " + ", ".join(line))

board_policy = {("bram", "normal"): "normal", ("bram", "ckpt"): "k3h3",
                ("nocheckpoint", "normal"): "normal", ("dram", "normal"): "session"}
for path in a.board:
    rows = list(csv.DictReader(open(path)))
    tally = defaultdict(lambda: [0, 0])
    for b in rows:
        pol = board_policy[(b["branch"], b["mode"])]
        k = (b["predicate"], int(b["target_count"]), int(b["seed_index"]))
        r = cpp[pol][k]
        same = (r["result_index"], r["trial_count"], r["L_BBHT"], r["actual_grover_iterations"]) == \
               (b["result_index"], b["trial_count"], b["L_BBHT"], b["actual_iter"])
        t = tally[(b["branch"], b["mode"])]
        t[0] += same; t[1] += 1
    for (br, mode), (g, n) in tally.items():
        ok_all &= g == n
        print(f"vs board {br}/{mode}: {g}/{n}")
print("PASS" if ok_all else "FAIL")
raise SystemExit(0 if ok_all else 1)
