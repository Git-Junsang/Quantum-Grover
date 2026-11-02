"""verify_cpp_oracles.py : oracle 4-type check of the C++ models (EQ / LT / GT / RANGE, DATA_COUNT padding).

For random datasets and thresholds the script compares
  1. the C++ target mask with the Python golden v098_target_mask,
  2. the C++ RTL-exact search (normal, k3h3) with the Python V098AutomaticCore,
  3. the C++ SW-best search (f64/f32, normal) result: success => index is a target;
     no targets => no success.
"""
import argparse, random, struct, subprocess, sys, tempfile
from pathlib import Path

import numpy as np

from repo_paths import GROVER_SINGLE, use_golden


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cases", type=int, default=40)
    ap.add_argument("--bin", default=str(GROVER_SINGLE))
    a = ap.parse_args()
    use_golden()
    from final_hardware_contract import V098RuntimeConfig
    from benchmark_dataset import V098Dataset, v098_target_mask
    from checkpoint_bbht_model import V098AutomaticCore

    rng = random.Random(20261002)
    stats = {"mask": 0, "rtl": 0, "sw": 0}
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        for case in range(a.cases):
            pred = ["EQ", "LT", "GT", "RANGE"][case % 4]
            count = rng.choice([16384, rng.randint(1, 16384)])
            data = np.array([rng.randint(-32768, 32767) for _ in range(16384)], dtype=np.int16)
            # Thresholds that give 0, a few, or many targets.
            if pred == "EQ":
                ta = int(data[rng.randrange(count)]) if case % 8 else 31999
                if case % 8:
                    for i in rng.sample(range(count), rng.choice([0, 3, 15])):
                        data[i] = ta
                tb = 0
            elif pred == "LT":
                ta, tb = rng.choice([-32768, -32700, -30000, 0]), 0
            elif pred == "GT":
                ta, tb = rng.choice([32767, 32700, 30000, 0]), 0
            else:
                lo = rng.randint(-32768, 32000)
                ta, tb = lo, lo + rng.choice([1, 2, 50, 4000])
            cfg = V098RuntimeConfig(predicate_mode=pred, threshold_a=ta, threshold_b=tb, data_count=count, auto_shot=True)
            py_mask = v098_target_mask(data, cfg)
            binp = Path(tmp) / "d.bin"
            binp.write_bytes(data.astype("<i2").tobytes())
            base = [a.bin, None, str(binp), pred, str(ta), str(tb), str(count)]
            out = subprocess.run([a.bin, "mask", *base[2:]], capture_output=True, text=True, check=True).stdout.split()
            cpp_idx = sorted(map(int, out))
            if cpp_idx != list(np.flatnonzero(py_mask)):
                bad.append(f"mask {pred} case {case}")
            else:
                stats["mask"] += 1
            ds = V098Dataset(memory_image=data, valid_values=data[:count], target_mask=py_mask,
                             target_indices=tuple(int(i) for i in np.flatnonzero(py_mask)), config=cfg,
                             layout="RANDOM_TEST", seed=case)
            sj, sm = rng.getrandbits(32), rng.getrandbits(32)
            for policy in ("normal", "k3h3"):
                py = V098AutomaticCore(ds, cfg.__class__(**{**cfg.__dict__, "seed_j": sj, "seed_meas": sm})).run_single(mode=policy.upper())
                res = subprocess.run([a.bin, "search", *base[2:], "rtl", policy, "f64", str(sj), str(sm)],
                                     capture_output=True, text=True, check=True).stdout.split()
                want = [str(int(py.success)), str(py.result_index if py.success else -1), str(py.trial_count),
                        str(py.L_BBHT), str(py.actual_grover_iterations)]
                if res != want:
                    bad.append(f"rtl {policy} {pred} case {case}: cpp={res} py={want}")
                else:
                    stats["rtl"] += 1
            for prec in ("f64", "f32"):
                res = subprocess.run([a.bin, "search", *base[2:], "sw", "normal", prec, str(sj), str(sm)],
                                     capture_output=True, text=True, check=True).stdout.split()
                success, idx = int(res[0]), int(res[1])
                ok = (success == 1 and py_mask[idx]) or (success == 0 and not py_mask.any()) or \
                     (success == 0 and py_mask.sum() > 0 and int(res[2]) > 0)
                if ok:
                    stats["sw"] += 1
                else:
                    bad.append(f"sw {prec} {pred} case {case}: {res}")
    print(f"cases {a.cases}: mask {stats['mask']}/{a.cases}, rtl search {stats['rtl']}/{2*a.cases}, "
          f"sw search valid {stats['sw']}/{2*a.cases}")
    for b in bad[:10]:
        print("  ", b)
    print("PASS" if not bad else "FAIL")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
