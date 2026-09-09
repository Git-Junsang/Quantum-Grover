#!/usr/bin/env python3
"""
최종 컷 -- 유력 후보만 남기고 나머지를 쳐냅니다.

세 관문을 순서대로 통과해야 남습니다.

  1. policy 게이트   결정당 action 이 K4/H4(79.46) 이하
  2. 용량            xc7a100t 의 BRAM 135 타일 안에 들어갈 것
  3. Pareto          (BRAM 타일, 총 사이클) 에서 지배당하지 않을 것

## BRAM 1차 산식

릴리스의 hierarchical 리포트에서 실제 값을 뽑았습니다.

    full SoC        RAMB36 82 + RAMB18 32  ->  98 타일 (README 와 일치)
    bbht_rvx_wrapper  RAMB36 50 + RAMB18 32  ->  66 타일
    u_main_ip         RAMB36 50 + RAMB18 32  ->  66 타일 (loader 는 BRAM 0)
    소자 한도                                     135 타일

Main IP 안에서 진폭 상태 하나가 11 RAMB36 입니다 (grover_checkpoint.v 머리말:
"11 RAMB36E1/state"). K4 는 checkpoint 4 + 작업본 1 = 5 상태입니다. 그러면

    타일 = RVX(32) + 상태수 x 11 + 엔진수 x 6 + 데이터메모리(5)

기준선에 넣으면 32 + 55 + 6 + 5 = 98 로 실측과 정확히 맞습니다. 엔진당 6 은
policy memo · row weight · result FIFO 몫이고, 데이터 메모리는 오라클이 같은
배열을 보므로 한 벌로 셉니다.

**이건 용량 1차 추정입니다.** 지시 17절이 금지한 exact bank identity 나 포트
충돌은 모델링하지 않았습니다. 다만 "소자에 들어가기는 하는가" 는 후보를 다음
단계로 넘기기 전에 봐야 하는 것이라 여기서 겁니다.
"""
from __future__ import annotations

import csv
import json
import os
import sys

DEVICE_TILES = 135
RVX_TILES = 32
TILES_PER_STATE = 11
TILES_PER_ENGINE = 6
DATA_MEM_TILES = 5

BASE_CYCLES = 8122630.0  # final_eval.py 의 K4/H4 모델값 (같은 잣대)


def tiles(states: int, engines: int) -> int:
    return RVX_TILES + states * TILES_PER_STATE + engines * TILES_PER_ENGINE + DATA_MEM_TILES


# final_eval.py 결과 + 상태수/엔진수
CANDS = [
    # 이름, 엔진, 상태수, 사이클, 결정당action, 비고
    ("K4/H4 (기준선)", 1, 5, 8122630, 79.46, "checkpoint 4 + 작업본 1"),
    ("K4/H6", 1, 5, 8039838, 78.29, ""),
    ("K3/H4", 1, 4, 7995668, 56.77, "checkpoint 3 + 작업본 1"),
    ("K5/H4", 1, 6, 8476802, 104.97, ""),
    ("K6/H4", 1, 7, 8761947, 123.38, ""),
    ("F1 C3+R2", 2, 5, 6259285, 59.78, "공유 C3 + 결과 슬롯 2"),
    ("F1 C4+R2", 2, 6, 6423889, 80.36, ""),
    ("F1 C5+R2", 2, 7, 6602395, 94.19, ""),
    ("F2 K2+K2", 2, 6, 6184503, 34.49, "track 마다 ckpt2 + 작업본1"),
    ("F2 K3+K2", 2, 7, 6074057, 41.37, "track A ckpt3, B ckpt2"),
    ("F2 K2+K3", 2, 7, 6135425, 39.57, ""),
    ("F2 K3+K3", 2, 8, 6023866, 46.45, ""),
]


def main() -> int:
    rows = []
    for name, engines, states, cycles, apd, note in CANDS:
        t = tiles(states, engines)
        rows.append(dict(name=name, engines=engines, states=states, cycles=cycles,
                         apd=apd, tiles=t, note=note))
    base = rows[0]

    for r in rows:
        r["gate"] = r["apd"] <= base["apd"]
        r["fits"] = r["tiles"] <= DEVICE_TILES

    print("=== 관문 1·2")
    print(f"{'후보':<16}{'E':>2}{'상태':>5}{'BRAM타일':>9}{'결정당act':>10}"
          f"{'policy':>8}{'용량':>7}")
    print("-" * 60)
    for r in rows:
        print(f"{r['name']:<16}{r['engines']:>2}{r['states']:>5}{r['tiles']:>9}"
              f"{r['apd']:>10.2f}"
              f"{('통과' if r['gate'] else '탈락'):>8}"
              f"{('통과' if r['fits'] else '초과'):>7}")

    alive = [r for r in rows if r["gate"] and r["fits"]]
    # Pareto: 더 적은 타일로 더 적은 사이클을 내는 것이 있으면 지배당합니다.
    front = []
    for r in alive:
        dominated = any(
            o is not r and o["tiles"] <= r["tiles"] and o["cycles"] <= r["cycles"]
            and (o["tiles"] < r["tiles"] or o["cycles"] < r["cycles"])
            for o in alive
        )
        r["pareto"] = not dominated
        if not dominated:
            front.append(r)

    print("\n=== 최종 유력 후보 (세 관문 전부 통과)")
    print(f"{'#':>2} {'후보':<16}{'E':>2}{'상태':>5}{'BRAM':>6}{'사이클':>12}"
          f"{'기준선대비':>11}  {'비고'}")
    print("-" * 84)
    for i, r in enumerate(sorted(front, key=lambda x: x["tiles"]), 1):
        print(f"{i:>2} {r['name']:<16}{r['engines']:>2}{r['states']:>5}"
              f"{r['tiles']:>5}/{DEVICE_TILES}{r['cycles']:>12,}"
              f"{100*(r['cycles']/BASE_CYCLES-1):>10.2f}%  {r['note']}")

    print("\n=== 쳐낸 것과 이유")
    for r in rows:
        if r is base or r.get("pareto"):
            continue
        if not r["gate"]:
            why = f"policy 게이트 탈락 ({r['apd']/base['apd']:.2f}x)"
        elif not r["fits"]:
            why = f"BRAM {r['tiles']} > {DEVICE_TILES} 타일 초과"
        else:
            better = min(
                (o for o in alive if o["tiles"] <= r["tiles"] and o["cycles"] <= r["cycles"]
                 and o is not r), key=lambda o: o["cycles"])
            why = f"{better['name']} 에 지배됨 (타일 {better['tiles']}, 사이클 {better['cycles']:,})"
        print(f"  {r['name']:<16} {why}")

    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "out", "shortlist.csv")
    with open(path, "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=["name", "engines", "states", "tiles",
                                          "cycles", "apd", "gate", "fits", "pareto", "note"])
        w.writeheader()
        for r in rows:
            r.setdefault("pareto", False)
            w.writerow({k: r[k] for k in w.fieldnames})
    print(f"\nraw {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
