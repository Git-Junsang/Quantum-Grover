#!/usr/bin/env python3
"""
equiv_check.py -- 체크포인트 없는 판의 NORMAL 이 체크포인트 판의 NORMAL 과 같은지

    python3 equiv_check.py <이 판 빌드 폴더> <기준 빌드 폴더> [술어 ...]

두 폴더의 pred_<술어>.csv (tb_predicate500.cpp 출력)를 워크로드마다 맞댑니다.

  이 판   hardware_bram_nocheckpoint 모델 어댑터
          (CHECKPOINT_ENABLE=0, INTRA_ENGINES=4, M1=M2=0)
  기준    hardware_bram_K3H3_E4 모델 어댑터 (보드 정본 K3/H3-E4-M2 에서 M1/M2 만 끈 것)
          (CHECKPOINT_ENABLE=1, K3/H3, INTRA_ENGINES=4) 의 NORMAL

체크포인트 판의 NORMAL 은 E4 진폭 메모리의 슬롯 0 만 쓰고 Planner/Executor/정책
엔진을 거치지 않습니다. 그러니 그 하드웨어를 generate 로 뺀 이 판과 결과 인덱스 ·
시도 수 · L_BBHT · 물리 반복은 물론 사이클과 STATUS 까지 같아야 합니다. 한 열이라도
다르면 체크포인트를 빼면서 다른 무엇이 바뀐 것입니다.

종료 코드: 전부 같으면 0, 아니면 1.
"""
import csv
import os
import sys

COLS = ("rc", "result_index", "result_value", "trial", "l_bbht", "iter", "cycles", "status")


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
    total = same = 0
    bad = []
    cyc_mine = cyc_ref = 0
    print("%-6s %6s %6s %8s  %14s" % ("술어", "기준", "이 판", "전 열 같음", "사이클 합"))
    for p in preds:
        a, b = load(mine, p), load(ref, p)
        keys = sorted(set(a) | set(b))
        n = ok = 0
        cyc = 0
        for k in keys:
            n += 1
            if k not in a or k not in b:
                bad.append("%s: %s 쪽에 없음" % (k, "이 판" if k not in a else "기준"))
                continue
            diff = [c for c in COLS if a[k][c] != b[k][c]]
            if diff:
                if len(bad) < 20:
                    bad.append("%s: %s" % (k, ", ".join("%s %s/%s" % (c, a[k][c], b[k][c]) for c in diff)))
            else:
                ok += 1
            cyc += int(a[k]["cycles"])
            cyc_mine += int(a[k]["cycles"])
            cyc_ref += int(b[k]["cycles"])
        total += n
        same += ok
        print("%-6s %6d %6d %8s  %14s" % (p, len(b), len(a), "%d/%d" % (ok, n), "{:,}".format(cyc)))
    print("\n사이클 합: 이 판 {:,} / 기준 {:,}".format(cyc_mine, cyc_ref))
    if bad:
        print("\n다른 것 (앞 20개)")
        for line in bad[:20]:
            print("  " + line)
    verdict = total > 0 and same == total and not bad
    print("\n판정: %s (%d/%d 워크로드가 %d 열 전부 같음)" % ("PASS" if verdict else "FAIL", same, total, len(COLS)))
    return 0 if verdict else 1


if __name__ == "__main__":
    sys.exit(main())
