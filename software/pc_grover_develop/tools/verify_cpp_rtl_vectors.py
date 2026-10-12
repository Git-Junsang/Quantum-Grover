"""verify_cpp_rtl_vectors.py : C++ model B core vs the 256 requested-j bit-exact RTL vectors.

Per case: target indices from the C++ oracle (data_memory_image + DATA_COUNT,
padding poison included) and the final Q1.22 amplitudes after requested_j
iterations, against expected_core.json / expected_final_amp.hex.
"""
import argparse, json, struct, subprocess, sys, tempfile, zipfile
from pathlib import Path

from repo_paths import GROVER_SINGLE, VECTORS_ZIP


def read_hex(path, bits):
    out = []
    for line in open(path):
        line = line.strip()
        if line:
            v = int(line, 16)
            out.append(v - (1 << bits) if v >= 1 << (bits - 1) else v)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vectors", default=str(VECTORS_ZIP), help="the 256-case zip or an unzipped dir")
    ap.add_argument("--bin", default=str(GROVER_SINGLE))
    a = ap.parse_args()
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        vec = Path(a.vectors)
        if vec.suffix == ".zip":
            zipfile.ZipFile(vec).extractall(Path(tmp) / "cases")
            vec = Path(tmp) / "cases"
        cases = sorted(p for p in vec.iterdir() if (p / "config.json").exists())
        for case in cases:
            cfg = json.load(open(case / "config.json"))["runtime_config"]
            exp = json.load(open(case / "expected_core.json"))
            data = read_hex(case / "data_memory_image.hex", 16)
            binp = Path(tmp) / "d.bin"
            binp.write_bytes(struct.pack("<16384h", *data))
            common = [a.bin, "", str(binp), cfg["predicate_mode"], str(cfg["threshold_a"]),
                      str(cfg["threshold_b"]), str(cfg["data_count"])]
            idx = subprocess.run([common[0], "mask", *common[2:]], capture_output=True, text=True, check=True).stdout.split()
            amps = subprocess.run([common[0], "core", *common[2:], str(cfg["j_target"])],
                                  capture_output=True, text=True, check=True).stdout.split()
            ok_mask = sorted(map(int, idx)) == sorted(exp["target_indices"])
            ok_amp = list(map(int, amps)) == read_hex(case / "expected_final_amp.hex", 23)
            if not (ok_mask and ok_amp):
                bad += 1
                print(f"MISMATCH {case.name}: mask={ok_mask} amplitudes={ok_amp}")
    print(f"requested-j vectors: {len(cases) - bad}/{len(cases)} bit-exact")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
