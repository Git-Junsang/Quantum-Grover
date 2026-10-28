#!/bin/bash
#
# 200 MHz 판(final_200mhz)을 RVX 플랫폼 bbht_grover_final_200mhz 에
# 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover_final_200mhz 로 갑니다.
#
# 순서
#   1. 공용 설치기(hardware_bram/rvx/install_model.sh)가 공용 src/ 와 이 판의
#      어댑터, 드라이버, 앱, 플랫폼 XML(clk_accel = 200 MHz)을 넣습니다
#   2. 이 판 src/ 의 RTL(200 MHz 용으로 레지스터 경계를 더한 파일)로 user/rtl/src
#      의 같은 이름 파일을 덮어씁니다. 이 판 src/ 에 없는 파일은 공용 것 그대로입니다
#   3. 드라이버가 사이클을 마이크로초로 바꿀 때 쓰는 BBHT_ACCEL_CLK_HZ 를 플랫폼
#      사본(user/api/bbht_grover_regs.h)에서만 200 MHz 로 바꿉니다. CSR 정본
#      (spec/bbht_grover_csr.json)과 저장소의 생성 헤더는 100 MHz 판의 것이라
#      건드리지 않습니다
#
# 앱은 bbht_console 과 bbht_paper_bench 를 올립니다. bbht_paper_bench 소스는
# 보드 정본과 sha256 이 같아야 해서 고치지 않습니다(CLAUDE.md 2절).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
CONFIGURATION=$(cd "$HERE/.." && pwd)
PLATFORM=${1:-${RVX_MINI_HOME:-/opt/rvx}/platform/bbht_grover_final_200mhz}

APPS="bbht_console bbht_paper_bench" "$HERE/../../../rvx/install_model.sh" "$CONFIGURATION" "$PLATFORM"

n=0
for f in "$CONFIGURATION"/src/*.v; do
    [ "$(basename "$f")" = bbht_grover_core_adapter.v ] && continue
    cp "$f" "$PLATFORM/user/rtl/src/"
    n=$((n + 1))
done
printf '  %-52s %s\n' "user/rtl/src" "200 MHz 판 RTL ${n}개로 덮어씀"

sed -i 's/^#define BBHT_ACCEL_CLK_HZ .*/#define BBHT_ACCEL_CLK_HZ   200000000u/' \
    "$PLATFORM/user/api/bbht_grover_regs.h"
grep -q '^#define BBHT_ACCEL_CLK_HZ   200000000u' "$PLATFORM/user/api/bbht_grover_regs.h" \
    || { echo "BBHT_ACCEL_CLK_HZ 를 200 MHz 로 바꾸지 못했습니다"; exit 1; }
printf '  %-52s %s\n' "user/api/bbht_grover_regs.h" "BBHT_ACCEL_CLK_HZ = 200 MHz"
