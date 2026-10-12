"""verify_baselines_vs_cpp.py : NumPy / Qiskit baseline runs vs the C++ SW float model of the same policy.

The checkpoint and all-j policies decide only from j values, and all float
backends share the J stream and the float sampler, so every workload must give
the same (result_index, trial_count, L_BBHT, physical iterations) as
CPP_SW_BEST_<POLICY>_F64. Workloads present in both files are compared
(a Qiskit run on a seed subset is fine).

  python3 tools/verify_baselines_vs_cpp.py --ref numpy_allj_*.csv --cpp sw_allj_f64_*.csv
"""
import argparse
import csv
import sys

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--ref", nargs="+", required=True, help="numpy_baseline.py / qiskit_baseline.py CSVs (one policy)")
ap.add_argument("--cpp", nargs="+", required=True, help="grover_bench --engine sw CSVs (same policy)")
a = ap.parse_args()


def load(paths):
    out, names = {}, set()
    for p in paths:
        for r in csv.DictReader(open(p)):
            names.add(r["backend"])
            out[(r.get("predicate") or "EQ", int(r["target_count"]), int(r["seed_index"]))] = (
                r["result_index"], r["trial_count"], r["L_BBHT"], r["actual_grover_iterations"])
    return out, names


ref, rn = load(a.ref)
cpp, cn = load(a.cpp)
common = sorted(set(ref) & set(cpp))
same = sum(ref[k] == cpp[k] for k in common)
phys_ref = sum(int(ref[k][3]) for k in common)
phys_cpp = sum(int(cpp[k][3]) for k in common)
print(f"{'/'.join(sorted(rn))} vs {'/'.join(sorted(cn))}: {same}/{len(common)} workloads identical "
      f"(result, trials, L, physical); physical iterations {phys_ref} vs {phys_cpp}")
for k in [k for k in common if ref[k] != cpp[k]][:5]:
    print("  mismatch", k, ref[k], cpp[k])
ok = common and same == len(common)
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
