#!/usr/bin/env python3
"""
250쌍 벤치 워크로드를 RTL 시뮬이 읽을 수 있는 형태로 떨굽니다.

보드 실측(`2026-09-04_k4h4_single_operator_final`)이 쓴 것과 같은 구성입니다.

    데이터셋  build_official_board_benchmark_dataset(M), M in {1,4,16,64,256}
    시드      seed_roster_50.json 의 (seed_j, seed_meas) 50쌍

내보내는 것:
    data_m<M>.bin   16,384개 little-endian int16
    seeds.txt       "seed_j seed_meas" 50줄

이 두 가지를 `hardware_bram/sim/tb_bench250.cpp` 가 WL_DIR 환경변수로 찾습니다.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.dirname(HERE)
ROSTER = os.path.join(GOLDEN, os.pardir,
                      "research", "multi_engine", "seed_roster_50.json")

TARGET_COUNTS = (1, 4, 16, 64, 256)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="내보낼 디렉터리")
    args = parser.parse_args()

    sys.path.insert(0, GOLDEN)
    import numpy as np
    from rtl_v098_data import build_official_board_benchmark_dataset

    os.makedirs(args.out, exist_ok=True)

    for target_count in TARGET_COUNTS:
        dataset = build_official_board_benchmark_dataset(target_count)
        image = np.asarray(dataset.memory_image, dtype="<i2")
        if image.size != 16384:
            print(f"M={target_count} 이미지 크기가 {image.size} 입니다", file=sys.stderr)
            return 1
        image.tofile(os.path.join(args.out, f"data_m{target_count}.bin"))

    with open(os.path.normpath(ROSTER), encoding="utf-8") as handle:
        roster = json.load(handle)
    if len(roster) != 50:
        print(f"시드가 {len(roster)}쌍입니다. 50쌍이어야 합니다", file=sys.stderr)
        return 1
    with open(os.path.join(args.out, "seeds.txt"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(f"{j} {meas}" for j, meas in roster) + "\n")

    print(f"데이터셋 {len(TARGET_COUNTS)}벌 + 시드 {len(roster)}쌍 -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
