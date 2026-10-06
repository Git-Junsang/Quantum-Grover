#!/bin/bash
#
# K3/H3-E4-M2 모델(hardware_bram_K3H3_E4_M2, 보드 정본 구성)을 RVX 플랫폼
# bbht_grover_upgrade 에 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover_upgrade 로 갑니다. 플랫폼
# 이름은 2026-09-07 보드 최종 빌드와 맞춘 것입니다 -- RVX 는 폴더 이름 · XML
# 이름 · user_region 파일 이름이 서로 같아야 합니다.
#
# 하는 일은 전부 공용 설치기 hardware_bram/rvx/install_model.sh 에 있습니다.
# 이 모델만 앱을 셋 올립니다.
#   bbht_console        UART 명령 셸
#   bbht_paper_bench    500런 실시간 벤치. 보드 실측(2026-09-08 묶음)을 낸 앱이고
#                       시드 로스터 100개가 안에 들어 있습니다
#   orca_sw_baseline    가속기를 안 쓰는 ORCA 1코어 기준선
#
# PJK 인수인계 §4.2 는 "RVX global tool 쪽 수정분을 source tree 밖의 임시
# 수정으로 두지 말고 재현 가능하게 관리" 하라고 요청합니다. 이 스크립트와
# 공용 설치기가 그 답입니다 -- 무엇을 어디에 넣는지가 전부 적혀 있고,
# 저장소에서 플랫폼으로 가는 방향만 있으므로 되돌리기도 쉽습니다.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
APPS="bbht_console bbht_paper_bench orca_sw_baseline" \
    exec "$HERE/../../../rvx/install_model.sh" "$HERE/.." "$@"
