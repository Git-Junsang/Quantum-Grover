#!/usr/bin/env python3

import argparse
import csv
import statistics
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("log", type=Path)
ap.add_argument("--expected", type=Path)
ap.add_argument("--out", type=Path, required=True)
a = ap.parse_args()

expected = {}

if a.expected and a.expected.exists():
    with a.expected.open(newline="") as f:
        for r in csv.DictReader(f):
            try:
                expected[
                    (int(r["target_count"]),
                     int(r["seed_index"]))
                ] = r
            except Exception:
                pass

rows = []

for raw in a.log.read_text(errors="replace").splitlines():

    line = raw.strip()

    if line.startswith("#"):
        line = line[1:].strip()

    if not line.startswith("SW_RUN,"):
        continue

    x = line.split(",")

    if len(x) != 14:
        print("BAD_SW_RUN_FIELD_COUNT", len(x), line)
        continue

    target = int(x[1], 0)
    seed = int(x[2], 0)

    hi = int(x[12], 0)
    lo = int(x[13], 0)

    ticks = (hi << 32) | lo

    r = {
        "target_count": target,
        "seed_index": seed,
        "seed_j": x[3],
        "seed_meas": x[4],
        "success": int(x[5], 0),
        "result_index": int(x[6], 0),
        "trial_count": int(x[7], 0),
        "L_BBHT": int(x[8], 0),
        "grover_iterations": int(x[9], 0),
        "termination": int(x[10], 0),
        "saturations": int(x[11], 0),
        "timer_hi": hi,
        "timer_lo": lo,
        "real_clock_ticks_us": ticks,
        "elapsed_sec": ticks / 1000000.0,
        "core50mhz_equiv_cycles": ticks * 50,
        "semantic_match": "N/A",
    }

    e = expected.get((target, seed))

    if e is not None:
        ok = True

        for k in ("result_index",
                  "trial_count",
                  "L_BBHT"):
            if k in e and str(e[k]).strip():
                if int(e[k], 0) != r[k]:
                    ok = False

        r["semantic_match"] = (
            "PASS" if ok else "FAIL"
        )

    rows.append(r)

fields = [
    "target_count",
    "seed_index",
    "seed_j",
    "seed_meas",
    "success",
    "result_index",
    "trial_count",
    "L_BBHT",
    "grover_iterations",
    "termination",
    "saturations",
    "timer_hi",
    "timer_lo",
    "real_clock_ticks_us",
    "elapsed_sec",
    "core50mhz_equiv_cycles",
    "semantic_match",
]

a.out.parent.mkdir(parents=True, exist_ok=True)

with a.out.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    w.writerows(rows)

print("rows =", len(rows))

checked = [
    r for r in rows
    if r["semantic_match"] in ("PASS", "FAIL")
]

passed = [
    r for r in checked
    if r["semantic_match"] == "PASS"
]

print(
    "semantic_match =",
    len(passed),
    "/",
    len(checked)
)

if rows:
    vals = [r["real_clock_ticks_us"] for r in rows]

    print("total_us =", sum(vals))
    print("mean_us  =", statistics.mean(vals))
    print("max_us   =", max(vals))
