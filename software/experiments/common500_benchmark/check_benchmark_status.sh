#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
JOURNAL="$ROOT/results/common500_final/software_resume_records.jsonl"

if [ ! -f "$JOURNAL" ]; then
  echo "저장된 Common500 소프트웨어 실행 기록이 없습니다."
  exit 0
fi

LINES=$(wc -l < "$JOURNAL")
echo "저장된 software backend 실행: $LINES / 2500"
echo "공통 workload 하나에는 software backend 5개가 기록됩니다."

if [ -f "$ROOT/results/common500_final/common500_validation_report.md" ]; then
  echo "최종 보고서: results/common500_final/common500_validation_report.md"
else
  echo "최종 보고서가 아직 없습니다."
fi
