#!/usr/bin/env bash
#
# 저장소 소스(src/)만으로 최종 Main IP 자원을 재 봅니다.
#
#   ./run_main_ip.sh
#
# K3/H3-E4-M2 파라미터로 OOC 합성해 synth/work_main_ip/util.rpt 를 남깁니다.
# 기대 규모는 results/2026-09-08_resource_ablation_5config/main_ip_5config.csv
# 의 k3h3_e4_m2 줄(LUT 33,730 / FF 28,258 / BRAM tile 84.0 / DSP 128)이지만,
# 그 표는 standalone top 안의 계층 사용량이라 OOC 와 조건이 다릅니다.
# 값이 몇 % 어긋나는 것은 정상이고, 자릿수가 달라지면 무언가 잘못된 것입니다.
#
# 헤드리스 환경이라 -mode batch 로만 돕니다.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/work_main_ip"

if [ -n "$VIVADO_BIN" ] && [ -x "$VIVADO_BIN" ]; then
  VIV="$VIVADO_BIN"
elif command -v vivado >/dev/null 2>&1; then
  VIV="$(command -v vivado)"
else
  echo "vivado 를 못 찾았습니다. VIVADO_BIN 을 지정하십시오."
  exit 3
fi

mkdir -p "$OUT"
SRC_DIR="$HERE/../src" OUTDIR="$OUT" \
  "$VIV" -mode batch -source "$HERE/main_ip_ooc.tcl" \
         -log "$OUT/vivado.log" -journal "$OUT/vivado.jou"

python3 "$HERE/parse_resource.py" --main-ip "$OUT/util.rpt"
