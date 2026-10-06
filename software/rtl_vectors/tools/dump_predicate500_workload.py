#!/usr/bin/env python3
"""
Predicate500 벤치가 읽는 자극을 떨굽니다 (네 술어 x M 다섯 개 x 시드 100쌍).

`hardware_bram/testbench/tb_predicate500.cpp` 와
`hardware_dram/testbench/tb_dram_predicate500.v` 가 읽는 파일을 만듭니다.

    pred_<P>_m<M>.bin        16,384개 little-endian int16
    pred_<P>_m<M>.hex        같은 내용을 $readmemh 용 4자리 16진 한 줄 한 값으로
    seeds.txt                "seed_j seed_meas" 십진 100줄
    workloads_<P>.txt        "<P> <술어코드> <A> <B> <M> <bin 경로>" 다섯 줄
    workloads_all.txt        위 넷을 LT GT EQ RANGE 순서로 이은 것

데이터셋은 software/models/common/benchmark_dataset.py 의
build_predicate_benchmark_dataset() 가 만듭니다. 보드 펌웨어의 GEN PRED=... 와
같은 규칙이고, 떨군 파일의 FNV-1a 가 기댓값 CSV(predicate500_datasets.csv)의 값과
같은지 여기서 확인합니다. 어긋나면 벤치 결과를 기댓값과 맞댈 수 없으므로 멈춥니다.

사용법:
    python3 dump_predicate500_workload.py --out DIR [--seeds 100]
"""
import argparse
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir))
SOFTWARE = os.path.join(REPO, "software")
sys.path.insert(0, os.path.join(SOFTWARE, "models", "common"))

from benchmark_dataset import (  # noqa: E402
    PREDICATE500_ORDER,
    PREDICATE500_SPECS,
    build_predicate_benchmark_dataset,
    fnv1a32_s16,
)

TARGET_COUNTS = (1, 4, 16, 64, 256)
PRED_CODES = {"LT": 0, "GT": 1, "EQ": 2, "RANGE": 3}
ROSTER_H = os.path.join(SOFTWARE, "experiments", "common500_benchmark", "inputs",
                        "official_board_seed_roster.h")
DATASETS_CSV = os.path.join(SOFTWARE, "experiments", "predicate500_benchmark",
                            "expected", "predicate500_datasets.csv")


def load_roster():
    text = open(ROSTER_H, encoding="utf-8").read()
    pairs = [(int(j, 16), int(m, 16))
             for j, m in re.findall(r"\{0x([0-9A-Fa-f]+)u\s*,\s*0x([0-9A-Fa-f]+)u\}", text)]
    if len(pairs) != 100:
        raise SystemExit("시드가 %d쌍입니다. 100쌍이어야 합니다" % len(pairs))
    return pairs


def load_expected_fnv():
    if not os.path.exists(DATASETS_CSV):
        raise SystemExit("기댓값이 없습니다. run_predicate500_golden.py 를 먼저 돌리십시오: %s"
                         % DATASETS_CSV)
    with open(DATASETS_CSV, encoding="utf-8") as f:
        return {(r["predicate"], int(r["target_count"])): int(r["dataset_fnv1a"], 16)
                for r in csv.DictReader(f)}


def main():
    ap = argparse.ArgumentParser(description="Predicate500 벤치 자극 생성")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seeds", type=int, default=100)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    expected = load_expected_fnv()

    with open(os.path.join(args.out, "seeds.txt"), "w") as f:
        for sj, sm in load_roster()[: args.seeds]:
            f.write("%d %d\n" % (sj, sm))

    all_lines = []
    for pred in PREDICATE500_ORDER:
        a, b, _ = PREDICATE500_SPECS[pred]
        lines = []
        for m in TARGET_COUNTS:
            ds = build_predicate_benchmark_dataset(pred, m)
            image = ds.memory_image
            got = fnv1a32_s16(image)
            if got != expected[(pred, m)]:
                raise SystemExit("%s M=%d FNV 0x%08x 가 기댓값 0x%08x 와 다릅니다"
                                 % (pred, m, got, expected[(pred, m)]))
            stem = os.path.join(args.out, "pred_%s_m%d" % (pred, m))
            with open(stem + ".bin", "wb") as f:
                f.write(image.astype("<i2").tobytes())
            with open(stem + ".hex", "w") as f:
                for v in image:
                    f.write("%04x\n" % (int(v) & 0xFFFF))
            lines.append("%s %d %d %d %d %s.bin\n" % (pred, PRED_CODES[pred], a, b, m, stem))
        with open(os.path.join(args.out, "workloads_%s.txt" % pred), "w") as f:
            f.writelines(lines)
        all_lines += lines
    with open(os.path.join(args.out, "workloads_all.txt"), "w") as f:
        f.writelines(all_lines)

    print("predicate500 자극: %d 데이터셋, 시드 %d쌍 -> %s"
          % (len(all_lines), args.seeds, args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
