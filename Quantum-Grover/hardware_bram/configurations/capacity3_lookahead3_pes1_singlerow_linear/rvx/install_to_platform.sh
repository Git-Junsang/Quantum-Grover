#!/bin/bash
#
# K3/H3-E1 모델(capacity3_lookahead3_pes1_singlerow_linear)을 RVX 플랫폼 bbht_grover_capacity3_lookahead3_pes1_singlerow_linear 에 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover_capacity3_lookahead3_pes1_singlerow_linear 로 갑니다. 하는 일은 전부
# 공용 설치기 hardware_bram/rvx/install_model.sh 에 있고, 이 모델에서 다른 것은
# ../src/bbht_grover_core_adapter.v 의 파라미터 기본값과 ../rvx/bbht_grover_capacity3_lookahead3_pes1_singlerow_linear.xml 의
# 플랫폼 이름뿐입니다. 앱은 둘을 올립니다.
#   bbht_console        UART 명령 셸
#   bbht_paper_bench    500런 실시간 벤치. 최종 모델(final)의 보드 실측을 낸 앱을
#                       그대로 써서 모델 사이 보드 측정을 같은 앱으로 맞춥니다. 앱은
#                       CONTROL 의 체크포인트 비트만 켜고 끄므로 K · H · E · M 이 달라도
#                       코드를 바꿀 필요가 없습니다 (소스는 한 글자도 고치지 않습니다)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
APPS="bbht_console bbht_paper_bench" exec "$HERE/../../../rvx/install_model.sh" "$HERE/.." "$@"
