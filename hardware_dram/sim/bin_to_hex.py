#!/usr/bin/env python3
"""
dump_bench_workload.py 가 내놓는 data_m<M>.bin (16비트 little-endian int16)
을 $readmemh 가 읽을 수 있는 4자리 16진 텍스트로 바꿉니다.

    python3 bin_to_hex.py <워크로드 디렉터리>

디렉터리 안의 data_m*.bin 을 전부 찾아 옆에 같은 이름의 .hex 를 만듭니다.
"""
import glob
import os
import struct
import sys


def convert(bin_path):
    hex_path = os.path.splitext(bin_path)[0] + ".hex"
    with open(bin_path, "rb") as f:
        raw = f.read()
    count = len(raw) // 2
    values = struct.unpack("<%dh" % count, raw)
    with open(hex_path, "w", encoding="utf-8") as f:
        for v in values:
            f.write("%04x\n" % (v & 0xFFFF))
    return hex_path


def main():
    if len(sys.argv) != 2:
        sys.exit("사용법: bin_to_hex.py <워크로드 디렉터리>")
    wl_dir = sys.argv[1]
    bins = sorted(glob.glob(os.path.join(wl_dir, "data_m*.bin")))
    if not bins:
        sys.exit("data_m*.bin 을 못 찾았습니다: %s" % wl_dir)
    for b in bins:
        convert(b)
    print("%d개 변환 완료" % len(bins))


if __name__ == "__main__":
    main()
