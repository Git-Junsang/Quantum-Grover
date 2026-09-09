#!/usr/bin/env bash
#
# 5구성 자원 ablation 재현 -- 재현 패키지가 있어야 합니다.
#
#   PKG=/경로/SERVER ./run_resource.sh
#
# 이 저장소에는 ablation 공통소스와 top 5벌이 없습니다 (결과표만
# results/2026-09-08_resource_ablation_5config/ 에 근거로 둡니다). 그래서
# 재현은 패키지 트리를 가리켜야 하고, 이 스크립트는 경로만 넘겨 줍니다.
#
# 저장소 소스만으로 최종 구성 하나를 재려면 run_main_ip.sh 를 쓰십시오.
set +e
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$PKG" ] || [ ! -d "$PKG/04_PUBLICATION_6STAGE" ]; then
  echo "PKG 에 재현 패키지 루트(SERVER/)를 주십시오."
  echo "  PKG=/경로/SERVER $0"
  exit 2
fi

PUB="$PKG/04_PUBLICATION_6STAGE"
CORE="$PUB/src"
INC="$PUB/include"
SUPPORT="$PKG/03_COMMON_SIM/rtl_support"
XDC="$PKG/07_STANDALONE_FPGA/constraints/bbht_standalone_arty100t.xdc"
OUT="$HERE/work"

if [ -n "$VIVADO_BIN" ] && [ -x "$VIVADO_BIN" ]; then
  VIV="$VIVADO_BIN"
elif command -v vivado >/dev/null 2>&1; then
  VIV="$(command -v vivado)"
else
  echo "vivado 를 못 찾았습니다. VIVADO_BIN 을 지정하십시오."
  exit 3
fi

mkdir -p "$OUT"; : > "$OUT/synth_status.tsv"
for CFG in k4h4_e1 k4h4_e4 k3h3_e4 k3h3_e4_m1 k3h3_e4_m2; do
  O="$OUT/$CFG"; mkdir -p "$O"
  CFG="$CFG" TOP_FILE="$PUB/tops/${CFG}_top.v" OUTDIR="$O" \
  CORE="$CORE" INCDIR="$INC" SUPPORT="$SUPPORT" XDC="$XDC" \
    "$VIV" -mode batch -source "$HERE/resource_synth.tcl" \
           -log "$O/vivado.log" -journal "$O/vivado.jou"
  printf "%s\t%s\n" "$CFG" "$?" | tee -a "$OUT/synth_status.tsv"
done
python3 "$HERE/parse_resource.py"
