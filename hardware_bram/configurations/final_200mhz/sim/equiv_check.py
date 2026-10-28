#!/usr/bin/env python3
"""
equiv_check.py -- 200 MHz 판이 100 MHz 판(보드 정본 구성)과 궤적이 같은지

    python3 equiv_check.py <200 MHz 빌드 폴더> <기준 빌드 폴더> [술어 ...]

두 폴더의 pred_<술어>.csv (tb_predicate500.cpp 출력)를 실행마다 맞댑니다.

  200 MHz 판  이 모델의 src/ (레지스터 경계를 더한 RTL) + 공용 src/ 의 나머지
  기준        공용 src/ + final 어댑터

200 MHz 판이 더한 것은 지연뿐이어야 합니다. 그래서 사이클을 뺀 모든 열
(rc · 결과 인덱스 · 값 · 시도 수 · L_BBHT · 물리 반복 · STATUS)이 같아야 하고,
사이클은 모드별 합과 그 비(200 MHz 판 / 기준)만 보고합니다. 사이클 비에 클럭 비 0.5 를
곱한 값이 같은 일을 하는 데 드는 시간의 비입니다.

종료 코드: 사이클을 뺀 전 열이 같으면 0, 아니면 1. 한쪽에만 있는 실행도 불일치입니다.
"""
import csv
import os
import sys
from collections import defaultdict

COLS = ("rc", "result_index", "result_value", "trial", "l_bbht", "iter", "status")


def load(folder, pred):
    path = os.path.join(folder, "pred_%s.csv" % pred)
    with open(path, encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(l for l in f if l.strip() and not l.startswith("#"))
                if r.get("predicate")]
    return {(r["predicate"], r["m"], r["seed_idx"], r["mode"]): r for r in rows}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    mine, ref = sys.argv[1], sys.argv[2]
    preds = sys.argv[3:] or ["LT", "GT", "EQ", "RANGE"]

    bad = 0
    total = 0
    cyc = defaultdict(lambda: [0, 0])
    for p in preds:
        a, b = load(mine, p), load(ref, p)
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                print("한쪽에만 있음:", k)
                bad += 1
                continue
            total += 1
            diff = [c for c in COLS if a[k][c] != b[k][c]]
            if diff:
                bad += 1
                if bad <= 20:
                    print("불일치", k, {c: (a[k][c], b[k][c]) for c in diff})
            cyc[k[3]][0] += int(a[k]["cycles"])
            cyc[k[3]][1] += int(b[k]["cycles"])

    print("실행 %d 개, 사이클 외 전 열 일치 %d / %d" % (total, total - bad, total))
    for mode, (c200, cref) in sorted(cyc.items()):
        r = c200 / cref if cref else float("nan")
        print("  %-6s 사이클 합  200MHz %12d  기준 %12d  비 %.4f  (시간 비 %.4f)"
              % (mode, c200, cref, r, r * 0.5))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
