#!/usr/bin/env python3
from pathlib import Path
import csv
import struct

DATA_COUNT = 16384
MAX_TARGET_COUNT = 256
TARGET_VALUE = 12345
BACKGROUND_SEED = 0x5EED1234
TARGET_POS_SEED = 0xA17E2026

def xorshift32(state):
    x = state & 0xffffffff
    if x == 0:
        x = 0x6D2B79F5
    x ^= (x << 13) & 0xffffffff
    x ^= x >> 17
    x ^= (x << 5) & 0xffffffff
    return x & 0xffffffff

def build():
    state = BACKGROUND_SEED
    data = []
    for _ in range(DATA_COUNT):
        state = xorshift32(state)
        v = state & 0xffff
        if v == TARGET_VALUE:
            v ^= 1
        data.append(v)

    state = TARGET_POS_SEED
    targets = []
    used = set()
    while len(targets) < MAX_TARGET_COUNT:
        state = xorshift32(state)
        idx = state & (DATA_COUNT - 1)
        if idx not in used:
            used.add(idx)
            targets.append(idx)
    return data, targets

def main():
    out = Path(__file__).resolve().parent / "reference_dataset"
    out.mkdir(exist_ok=True)

    base, targets = build()

    with (out / "target_indices_256.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["rank", "index"])
        for rank, idx in enumerate(targets):
            w.writerow([rank, idx])

    for tc in [1, 4, 16, 64, 256]:
        data = list(base)
        for idx in targets[:tc]:
            data[idx] = TARGET_VALUE
        with (out / f"dataset_target_{tc}.bin").open("wb") as f:
            for v in data:
                f.write(struct.pack("<H", v))
        with (out / f"dataset_target_{tc}.csv").open("w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["index", "value", "is_target"])
            target_set = set(targets[:tc])
            for i, v in enumerate(data):
                w.writerow([i, v if v < 0x8000 else v - 0x10000, int(i in target_set)])

    print(out)

if __name__ == "__main__":
    main()
