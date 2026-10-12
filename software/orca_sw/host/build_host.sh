#!/usr/bin/env bash
# 저장소의 ORCA SW 기준선 소스를 손대지 않고 서버(x86-64)에서 빌드합니다.
# RVX 헤더 셋(platform_info.h, ervp_printf.h, ervp_real_clock.h)만 stub/ 로 바꿔 끼웁니다.
#
#   build_host.sh <앱> <출력이름> [매크로=값 ...]
#   예) build_host.sh orca_bbht_opt_normal normal_full PROFILE=1
#       taskset -c 4 /tmp/orca_host_bin/normal_full > normal_full.log
#
# 매크로는 baseline_config.h 의 BBHT_ 뒤 이름입니다(PROFILE, CALIB_ITERS, SUBSET_PRED_MASK ...).
# 출력 형식은 보드와 같고, 끝에 HOST_CYCLES,<순번>,<사이클> 줄이 SW_RUN 순서대로 붙습니다
# (stub/ervp_real_clock.h). 머리줄의 RVX_REAL_CLOCK · 50000000 은 main.c 의 고정 문자열이라
# 서버에서도 그대로 찍힙니다.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
APP="$1"; OUT="$2"; shift 2
SRC="$REPO/software/orca_sw/$APP/src"
DEFS=()
for kv in "$@"; do
    DEFS+=("-DBBHT_${kv%%=*}=${kv#*=}")
done
BIN="${ORCA_HOST_BIN:-/tmp/orca_host_bin}"   # 실행 파일은 저장소 밖에 둡니다
mkdir -p "$BIN"
# ORCA release 빌드와 같은 최적화(-O2)와 같은 코드 생성 옵션. -march 만 다릅니다(x86-64 기본).
gcc -O2 -ffunction-sections -fdata-sections -fno-delete-null-pointer-checks -fno-builtin-printf \
    -fno-reorder-functions -Wall -Wno-format -I"$HERE/stub" "${DEFS[@]}" \
    "$SRC"/*.c -o "$BIN/$OUT"
echo "$BIN/$OUT"
