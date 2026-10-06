"""Write the 20 Predicate500 datasets (4 predicates x M=1/4/16/64/256) as int16 .bin.

Uses the team generator (benchmark_dataset.build_predicate_benchmark_dataset,
the twin of the board console's GEN command) and checks every image against the
FNV-1a / sha256 in software/experiments/predicate500_benchmark/expected/predicate500_datasets.csv.
sw_benchmark already ships the 20 files in data/predicate500_datasets; this tool
regenerates them (default) or writes them elsewhere (--out) and proves they match.
"""
import argparse, csv, hashlib, sys
from pathlib import Path

from repo_paths import P500_DATASETS, P500_EXPECTED, use_golden

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument("--out", default=str(P500_DATASETS))
a = ap.parse_args()
use_golden()
from benchmark_dataset import PREDICATE500_ORDER, PREDICATE500_SPECS, build_predicate_benchmark_dataset, fnv1a32_s16

ref = {(r["predicate"], int(r["target_count"])): r
       for r in csv.DictReader(open(P500_EXPECTED / "predicate500_datasets.csv"))}
out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
bad = 0
for pred in PREDICATE500_ORDER:
    A, B, _ = PREDICATE500_SPECS[pred]
    for m in (1, 4, 16, 64, 256):
        ds = build_predicate_benchmark_dataset(pred, m)
        raw = ds.memory_image.astype("<i2").tobytes()
        (out / f"dataset_{pred}_target_{m}.bin").write_bytes(raw)
        r = ref[(pred, m)]
        ok = f"0x{fnv1a32_s16(ds.memory_image):08x}" == r["dataset_fnv1a"].lower() and \
             hashlib.sha256(raw).hexdigest() == r["dataset_sha256"]
        bad += not ok
        print(f"{pred:5s} M={m:3d} A={A} B={B} fnv/sha256 {'OK' if ok else 'MISMATCH'}")
print("all 20 datasets match predicate500_datasets.csv" if not bad else f"{bad} MISMATCH")
sys.exit(1 if bad else 0)
