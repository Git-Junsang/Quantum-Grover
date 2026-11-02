#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(cd "$HERE/../.." && pwd)/reference_model_data/2026-09-11_common500
JOURNAL="$OUT/software_resume_records.jsonl"

if [ ! -f "$JOURNAL" ]; then
  echo "저장된 Common500 소프트웨어 실행 기록이 없습니다."
  exit 0
fi

LINES=$(wc -l < "$JOURNAL")
echo "저장된 software backend 실행: $LINES / 2500"
echo "공통 workload 하나에는 software backend 5개가 기록됩니다."

if [ -f "$OUT/2026-09-11_common500.md" ]; then
  echo "최종 보고서: $OUT/2026-09-11_common500.md"
else
  echo "최종 보고서가 아직 없습니다."
fi
