#!/bin/bash
#
# K4/H4-E1 모델(hardware_bram_K4H4_E1)을 RVX 플랫폼 bbht_grover_k4h4_e1 에 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover_k4h4_e1 로 갑니다. 하는 일은 전부
# 공용 설치기 hardware_bram/rvx/install_model.sh 에 있고, 이 모델에서 다른 것은
# ../src/bbht_grover_core_adapter.v 의 파라미터 기본값과 ../rvx/bbht_grover_k4h4_e1.xml 의
# 플랫폼 이름뿐입니다. 앱은 bbht_console 하나만 올립니다.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
APPS="bbht_console" exec "$HERE/../../../rvx/install_model.sh" "$HERE/.." "$@"
