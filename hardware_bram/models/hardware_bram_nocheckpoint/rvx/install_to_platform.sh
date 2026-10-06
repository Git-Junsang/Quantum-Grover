#!/bin/bash
#
# 체크포인트 없는 판(hardware_bram_nocheckpoint, Normal-E4)을 RVX 플랫폼
# bbht_grover_nocheckpoint 에 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover_nocheckpoint 로 갑니다.
# 하는 일은 전부 공용 설치기 hardware_bram/rvx/install_model.sh 에 있고, 이
# 판에서 다른 것은 ../src/bbht_grover_core_adapter.v 하나입니다
# (CHECKPOINT_ENABLE=0 · INTRA_ENGINES=4 · MEAS_M1/M2=0, burst 요청을 Main IP 에
# 넘기지 않음). 앱은 bbht_console 하나만 올립니다. bbht_paper_bench 와
# orca_sw_baseline 은 보드 정본 실측용이라 이 판에서 돌릴 이유가 없습니다.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
grep -q "CHECKPOINT_ENABLE  = 0" "$HERE/../src/bbht_grover_core_adapter.v" \
    || { echo "이 판 어댑터가 체크포인트 없는 구성이 아닙니다"; exit 1; }
APPS="bbht_console" exec "$HERE/../../../rvx/install_model.sh" "$HERE/.." "$@"
