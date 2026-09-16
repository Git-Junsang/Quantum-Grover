#!/usr/bin/env python3
"""
250쌍 · 500 워크로드 벤치가 읽는 자극을 저장소 안의 재료에서 떨굽니다.

`hardware_bram/testbench/tb_bench250.cpp` 와 `tb_bench500.cpp` 가 WL_DIR
환경변수로 찾는 두 가지를 만듭니다.

    data_m<M>.bin   16,384개 little-endian int16, M in {1,4,16,64,256}
    seeds.txt       "seed_j seed_meas" 십진 50줄 또는 100줄

옛 `software/golden/tools/dump_bench250_workload.py` 를 대신합니다. 그쪽은
데이터셋을 numpy 로 다시 계산하고(`build_official_board_benchmark_dataset`)
시드를 `software/research/multi_engine/seed_roster_50.json` 에서 읽었는데,
둘 다 2026-09-13 재편 때 저장소에서 빠졌습니다. 500쌍 판은 애초에 커밋된 적이
없습니다.

다시 계산할 이유가 없다는 것을 확인해서 이렇게 바꿨습니다.

  - 데이터셋 다섯 개는 `software/experiments/common500_benchmark/inputs/datasets/`
    에 있고, `hardware_bram/firmware/bbht_paper_bench/tools/reference_dataset/`
    의 것과 sha256 이 5/5 같습니다. 즉 보드가 실제로 쓴 바로 그 바이트입니다.
    그러니 계산하지 않고 그대로 복사합니다 -- numpy 도 필요 없습니다.
  - 시드 100쌍은 보드 벤치 앱이 쓴 `official_board_seed_roster.h` 에 있고,
    `hardware_bram/results/2026-09-08_publication_6stage/seeds.csv` 의 100쌍과
    같습니다. 250쌍 벤치가 쓰던 50쌍은 이 100쌍의 앞 50쌍입니다.

그래서 이 도구는 표준 라이브러리만 씁니다.

사용법:
    python3 dump_bench_workload.py --out DIR --seeds 50     # bench250
    python3 dump_bench_workload.py --out DIR --seeds 100    # bench500
"""
import argparse
import csv
import hashlib
import os
import re
import shutil
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir))

INPUTS = os.path.join(REPO, "software", "experiments", "common500_benchmark", "inputs")
DATASET_DIR = os.path.join(INPUTS, "datasets")
ROSTER_H = os.path.join(INPUTS, "official_board_seed_roster.h")

# 두 번째 출처. 같은 시드 100쌍을 다른 형식으로 들고 있어서 교차검증에 씁니다.
SEEDS_CSV = os.path.join(REPO, "hardware_bram", "results",
                         "2026-09-08_publication_6stage", "seeds.csv")

TARGET_COUNTS = (1, 4, 16, 64, 256)
N_ENTRIES = 16384           # Q = 14
BYTES_PER_DATASET = N_ENTRIES * 2

# 보드 500런·6단계 ablation 캠페인이 쓴 바로 그 데이터셋의 해시입니다. 입력이
# 조용히 바뀌면 벤치 수치가 기존 근거 묶음과 안 맞게 되므로 여기서 못박습니다.
DATASET_SHA256 = {
    1:   "49ed208e31f5e64d5e0a5048bfa118a134883f8c0f4ac744946c13362bdb91b3",
    4:   "39f050c4ce2ecf51766022f8a7fa2bac736987933613130a208fc2c44d220367",
    16:  "6ca57cbc428c72f64e9f9fb3e812ab8090f3ee769512335e7cf85742266e988f",
    64:  "903e997ee650f880d95f8e2a2b704933825f7649bee07d476a05036e8b5db455",
    256: "7903ef48c95182fe3d05dfbf72818314113b8c65832c2adb9a870faf50314539",
}

ROSTER_SIZE = 100


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_datasets():
    """검증 1·2 -- 크기와 해시. 둘 중 하나라도 어긋나면 바로 세웁니다."""
    problems = []
    for m in TARGET_COUNTS:
        path = os.path.join(DATASET_DIR, "dataset_target_%d.bin" % m)
        if not os.path.exists(path):
            problems.append("M=%d 데이터셋이 없습니다: %s" % (m, path))
            continue
        size = os.path.getsize(path)
        if size != BYTES_PER_DATASET:
            problems.append("M=%d 가 %d 바이트입니다. %d 이어야 합니다 (int16 x %d)"
                            % (m, size, BYTES_PER_DATASET, N_ENTRIES))
            continue
        got = sha256_of(path)
        if got != DATASET_SHA256[m]:
            problems.append("M=%d sha256 이 %s 입니다. 캠페인이 쓴 것은 %s 입니다"
                            % (m, got[:16], DATASET_SHA256[m][:16]))
    return problems


def load_roster():
    """검증 3 -- 보드 앱 헤더에서 시드 100쌍을 뽑습니다."""
    if not os.path.exists(ROSTER_H):
        raise SystemExit("시드 로스터가 없습니다: %s" % ROSTER_H)
    text = open(ROSTER_H, encoding="utf-8").read()
    pairs = [(int(j, 16), int(meas, 16))
             for j, meas in re.findall(r"\{0x([0-9A-Fa-f]+)u\s*,\s*0x([0-9A-Fa-f]+)u\}", text)]
    if len(pairs) != ROSTER_SIZE:
        raise SystemExit("시드가 %d쌍입니다. %d쌍이어야 합니다 (%s)"
                         % (len(pairs), ROSTER_SIZE, ROSTER_H))
    return pairs


def crosscheck_roster(pairs):
    """검증 4 -- 6단계 캠페인의 seeds.csv 와 같은 100쌍인가."""
    if not os.path.exists(SEEDS_CSV):
        return ["교차검증용 seeds.csv 가 없습니다: %s" % SEEDS_CSV]
    with open(SEEDS_CSV, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    other = [(int(r["seed_j"], 16), int(r["seed_meas"], 16)) for r in rows]
    if other == pairs:
        return []
    problems = ["seeds.csv 와 로스터가 다릅니다 (%d쌍 대 %d쌍)" % (len(other), len(pairs))]
    for i, (a, b) in enumerate(zip(pairs, other)):
        if a != b:
            problems.append("  시드 %d: 헤더 (0x%08X, 0x%08X) vs csv (0x%08X, 0x%08X)"
                            % (i, a[0], a[1], b[0], b[1]))
            if len(problems) > 6:
                break
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="내보낼 디렉터리")
    ap.add_argument("--seeds", type=int, default=ROSTER_SIZE, choices=(50, ROSTER_SIZE),
                    help="시드 쌍 수. 50 = bench250, 100 = bench500 (기본 100)")
    args = ap.parse_args()

    problems = check_datasets()
    if problems:
        for p in problems:
            print("오류: %s" % p, file=sys.stderr)
        return 1
    print("확인  데이터셋 5벌 -- 각 %d 바이트, sha256 캠페인 값과 일치" % BYTES_PER_DATASET)

    roster = load_roster()
    print("확인  시드 로스터 %d쌍 파싱" % len(roster))

    problems = crosscheck_roster(roster)
    if problems:
        for p in problems:
            print("오류: %s" % p, file=sys.stderr)
        return 1
    print("확인  로스터 == results/2026-09-08_publication_6stage/seeds.csv (%d/%d)"
          % (len(roster), len(roster)))

    seeds = roster[:args.seeds]
    # 검증 5 -- 250쌍이 500 워크로드의 부분집합이라는 불변식. 이것이 깨지면
    # bench250 과 bench500 을 같은 축에서 비교할 수 없게 됩니다.
    if seeds != roster[:len(seeds)]:
        print("오류: 앞 %d쌍 부분집합 불변식이 깨졌습니다" % len(seeds), file=sys.stderr)
        return 1
    print("확인  앞 %d쌍이 100쌍의 부분집합 (bench250 ⊂ bench500)" % len(seeds))

    os.makedirs(args.out, exist_ok=True)

    for m in TARGET_COUNTS:
        src = os.path.join(DATASET_DIR, "dataset_target_%d.bin" % m)
        dst = os.path.join(args.out, "data_m%d.bin" % m)
        shutil.copyfile(src, dst)
        # 복사가 온전한지 마지막으로 한 번 더. 내보낸 것이 근거가 되므로
        # 입력만 검사하고 끝내지 않습니다.
        if sha256_of(dst) != DATASET_SHA256[m]:
            print("오류: 복사한 data_m%d.bin 의 해시가 다릅니다" % m, file=sys.stderr)
            return 1

    # tb_bench*.cpp 가 fscanf("%u %u") 로 읽습니다 -- 십진이어야 합니다.
    with open(os.path.join(args.out, "seeds.txt"), "w", encoding="utf-8") as f:
        f.write("".join("%u %u\n" % pair for pair in seeds))

    print("데이터셋 %d벌 + 시드 %d쌍 -> %s" % (len(TARGET_COUNTS), len(seeds), args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
