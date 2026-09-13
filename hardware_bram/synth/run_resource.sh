#!/usr/bin/env bash
#
# 5구성 자원 ablation 재현 (Vivado, 합성까지만).
#
#   ./run_resource.sh
#
# 대상 top 5벌, ablation 공통소스, 공통 XDC 가 전부 ../src_ablation/ 에
# 있습니다. 2026-09-13 에 재현 패키지를 풀어 저장소 안으로 들였으므로
# 패키지 트리 없이 돕니다. XDC 는 standalone 판의 것을 그대로 쓰는데, 원 캠페인이
# 다섯 구성을 standalone top 틀 안에서 합성했기 때문입니다.
#
# 결과는 work/<구성>/ 에 남고, 마지막에 parse_resource.py 가
# results/2026-09-08_resource_ablation_5config/ 의 값과 대조합니다. 그 표는
# Vivado 2024.2 에서 나온 것이라 버전이 다르면 값이 조금씩 어긋날 수 있습니다.
#
# 저장소 정본 src/ 만으로 최종 구성 하나를 재려면 run_main_ip.sh 를 쓰십시오.
set +e
HERE="$(cd "$(dirname "$0")" && pwd)"

# ablation 폴더 하나에 공통소스·include·top·UART 브리지·데이터셋 생성기가 다
# 있어서 네 경로가 같습니다. resource_synth.tcl 이 역할별로 받게 되어 있어
# 그대로 따로 넘깁니다.
ABL="$(cd "$HERE/../src_ablation" && pwd)"
CORE="$ABL"
INC="$ABL"
SUPPORT="$ABL"
TOPS="$ABL"
XDC="$ABL/bbht_standalone_arty100t.xdc"
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
  CFG="$CFG" TOP_FILE="$TOPS/${CFG}_top.v" OUTDIR="$O" \
  CORE="$CORE" INCDIR="$INC" SUPPORT="$SUPPORT" XDC="$XDC" \
    "$VIV" -mode batch -source "$HERE/resource_synth.tcl" \
           -log "$O/vivado.log" -journal "$O/vivado.jou"
  printf "%s\t%s\n" "$CFG" "$?" | tee -a "$OUT/synth_status.tsv"
done
python3 "$HERE/parse_resource.py"
