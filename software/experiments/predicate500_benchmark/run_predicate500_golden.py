#!/usr/bin/env python3
"""Predicate500 기댓값 생성기 -- 네 술어 x 500 워크로드의 SW 기준 결과.

Common500 은 EQ 술어 하나로 M = 1/4/16/64/256 x 공식 시드 100쌍 = 500 워크로드를
돌렸습니다. Predicate500 은 같은 모양을 LT / GT / EQ / RANGE 네 술어에 각각
적용해 2,000 워크로드를 만듭니다. EQ 500개는 Common500 과 데이터셋·시드가 바이트
단위로 같습니다.

기댓값은 Q1.22 bit-exact 기준모델(`V098AutomaticCore`)이 냅니다. 이 모델은
Common500 에서 보드 M2 와 result_index · trial_count · L_BBHT ·
actual_grover_iterations 가 500/500 맞았습니다. NumPy 부동소수 모델은 측정
난수 규칙이 달라 궤적이 다르므로 기댓값으로 쓰지 않습니다.

모드 셋을 모두 돌립니다.
  NORMAL      bram NORMAL_SINGLE (burst_enable=0) 과 dram 단일 탐색
  K3H3        bram CKPT_SINGLE (K3/H3-E4-M2) 의 물리 반복
  DRAM_ALL_J  dram 갈래의 물리 반복 (모든 j 를 DRAM 에서 복원)
논리 궤적(result_index · trial_count · L_BBHT)은 모드와 무관해야 하므로 셋이
같은지 여기서 확인하고, 물리 반복만 모드별 열로 남깁니다.

dram 갈래는 열이 둘입니다.
  actual_iter_dram_all_j    탐색마다 DRAM 표를 비우고 시작한 값
  actual_iter_dram_session  한 데이터셋을 적재한 뒤 시드 0 부터 차례로 돌 때
                            DRAM 표를 이어 쓴 값. 실물 RTL 은 적재나 술어가
                            바뀔 때만 표를 버리므로 보드·RTL 하네스(데이터셋
                            하나에 시드 100개 연속)는 이 열과 맞아야 합니다

출력 (기본 위치는 이 폴더의 expected/)
  predicate500_expected.csv   워크로드 2,000행
  predicate500_datasets.csv   데이터셋 20개의 임계값 · 시드 · FNV-1a · sha256

보드 쪽 자동 테스트(software/host/bbht_predicate500.py)가 이 두 파일을 읽습니다.
그래서 호스트 PC 에는 numpy 없이 pyserial 과 openpyxl 만 있으면 됩니다.

사용법:
    PYTHONPATH=software/models/common:software/models/rtl_reference_model \
        python3 software/experiments/predicate500_benchmark/run_predicate500_golden.py
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import sys
import time
from dataclasses import replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
for sub in ("models/common", "models/rtl_reference_model"):
    path = str(SOFTWARE / sub)
    if path not in sys.path:
        sys.path.insert(0, path)

from benchmark_dataset import (  # noqa: E402
    PREDICATE500_BACKGROUND_SEED,
    PREDICATE500_ORDER,
    PREDICATE500_SPECS,
    build_predicate_benchmark_dataset,
    fnv1a32_s16,
    predicate_hit,
)
from checkpoint_bbht_model import V098AllJCheckpointReference, V098AutomaticCore  # noqa: E402

TARGET_COUNTS = (1, 4, 16, 64, 256)
ROSTER_H = SOFTWARE / "experiments" / "common500_benchmark" / "inputs" / "official_board_seed_roster.h"
MODES = ("NORMAL", "K3H3", "DRAM_ALL_J")

EXPECTED_FIELDS = (
    "predicate", "threshold_a", "threshold_b", "target_count", "seed_index",
    "seed_j", "seed_meas", "dataset_fnv1a",
    "success", "termination_reason", "result_index", "result_value",
    "trial_count", "L_BBHT",
    "actual_iter_normal", "actual_iter_k3h3", "actual_iter_dram_all_j",
    "actual_iter_dram_session",
)
DATASET_FIELDS = (
    "predicate", "threshold_a", "threshold_b", "target_count",
    "bg_seed", "pos_seed", "gen_command", "dataset_fnv1a", "dataset_sha256",
    "first_targets",
)


def load_roster(path: Path = ROSTER_H) -> list[tuple[int, int]]:
    text = path.read_text(encoding="utf-8")
    pairs = [
        (int(j, 16), int(m, 16))
        for j, m in re.findall(r"\{0x([0-9A-Fa-f]+)u\s*,\s*0x([0-9A-Fa-f]+)u\}", text)
    ]
    if len(pairs) != 100:
        raise SystemExit(f"seed roster must have 100 pairs, got {len(pairs)}")
    return pairs


def gen_command(mode: str, target_count: int) -> str:
    """보드 콘솔에 보낼 GEN 명령. 호스트 프로그램이 이 열을 그대로 씁니다."""

    a, b, pos_seed = PREDICATE500_SPECS[mode]
    parts = [f"GEN PRED={mode} A={a}"]
    if mode == "RANGE":
        parts.append(f"B={b}")
    parts.append(f"TARGETS={target_count}")
    parts.append(f"SEED=0x{PREDICATE500_BACKGROUND_SEED:08X}")
    parts.append(f"POS=0x{pos_seed:08X}")
    return " ".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, default=HERE / "expected")
    ap.add_argument("--predicates", default=",".join(PREDICATE500_ORDER))
    ap.add_argument("--seeds", type=int, default=100,
                    help="앞에서부터 몇 쌍을 쓸지 (시험용. 정본은 100)")
    args = ap.parse_args()

    predicates = [p.strip().upper() for p in args.predicates.split(",") if p.strip()]
    roster = load_roster()[: args.seeds]
    args.out.mkdir(parents=True, exist_ok=True)

    expected_rows: list[dict[str, object]] = []
    dataset_rows: list[dict[str, object]] = []
    started = time.perf_counter()

    for mode in predicates:
        a, b, pos_seed = PREDICATE500_SPECS[mode]
        for m in TARGET_COUNTS:
            ds = build_predicate_benchmark_dataset(mode, m)
            image = ds.memory_image
            fnv = fnv1a32_s16(image)
            dataset_rows.append({
                "predicate": mode,
                "threshold_a": a,
                "threshold_b": b,
                "target_count": m,
                "bg_seed": f"0x{PREDICATE500_BACKGROUND_SEED:08x}",
                "pos_seed": f"0x{pos_seed:08x}",
                "gen_command": gen_command(mode, m),
                "dataset_fnv1a": f"0x{fnv:08x}",
                "dataset_sha256": hashlib.sha256(image.astype("<i2").tobytes()).hexdigest(),
                "first_targets": " ".join(str(i) for i in ds.target_indices[:8]),
            })
            # 데이터셋 하나에 표 하나. 시드를 차례로 돌며 이어 씁니다.
            dram_session = V098AllJCheckpointReference()
            for seed_index, (seed_j, seed_meas) in enumerate(roster):
                cfg = replace(ds.config, seed_j=seed_j, seed_meas=seed_meas, shot_cap=100)
                core = V098AutomaticCore(ds, cfg)
                results = {name: core.run_single(mode=name) for name in MODES}
                results["DRAM_SESSION"] = core.run_single(
                    mode="DRAM_ALL_J", checkpoint=dram_session)
                ref = results["NORMAL"]
                for name, res in results.items():
                    logical = (res.success, res.result_index, res.trial_count, res.L_BBHT)
                    if logical != (ref.success, ref.result_index, ref.trial_count, ref.L_BBHT):
                        raise SystemExit(
                            f"{mode} M={m} seed={seed_index}: {name} logical trajectory "
                            f"{logical} differs from NORMAL"
                        )
                value = int(image[ref.result_index]) if ref.success else ""
                if ref.success and not predicate_hit(mode, int(value), a, b):
                    raise SystemExit(f"{mode} M={m} seed={seed_index}: result fails predicate")
                expected_rows.append({
                    "predicate": mode,
                    "threshold_a": a,
                    "threshold_b": b,
                    "target_count": m,
                    "seed_index": seed_index,
                    "seed_j": f"0x{seed_j:08x}",
                    "seed_meas": f"0x{seed_meas:08x}",
                    "dataset_fnv1a": f"0x{fnv:08x}",
                    "success": int(ref.success),
                    "termination_reason": ref.termination_reason,
                    "result_index": "" if ref.result_index is None else ref.result_index,
                    "result_value": value,
                    "trial_count": ref.trial_count,
                    "L_BBHT": ref.L_BBHT,
                    "actual_iter_normal": results["NORMAL"].actual_grover_iterations,
                    "actual_iter_k3h3": results["K3H3"].actual_grover_iterations,
                    "actual_iter_dram_all_j": results["DRAM_ALL_J"].actual_grover_iterations,
                    "actual_iter_dram_session": results["DRAM_SESSION"].actual_grover_iterations,
                })
            print(f"{mode:5s} M={m:3d}  {len(roster)} seeds  fnv=0x{fnv:08x}  "
                  f"{time.perf_counter() - started:6.1f}s", flush=True)

    with open(args.out / "predicate500_expected.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=EXPECTED_FIELDS, lineterminator="\n")
        w.writeheader()
        w.writerows(expected_rows)
    with open(args.out / "predicate500_datasets.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=DATASET_FIELDS, lineterminator="\n")
        w.writeheader()
        w.writerows(dataset_rows)

    ok = sum(int(r["success"]) for r in expected_rows)
    print(f"{len(expected_rows)} workloads, success {ok}, written to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
