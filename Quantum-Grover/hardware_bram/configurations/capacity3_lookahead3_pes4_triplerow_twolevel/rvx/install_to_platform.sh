#!/bin/bash
#
# K3/H3-E4-M3 모델(3행 BUILD + M2 16x32 SELECT)을 별도 RVX 플랫폼에
# 설치합니다. 기존 M2 정본 bbht_grover_final를 덮어쓰지 않습니다.
#
#   ./install_to_platform.sh [플랫폼경로]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
APPS="bbht_console bbht_paper_bench orca_sw_baseline" \
    exec "$HERE/../../../rvx/install_model.sh" "$HERE/.." "$@"
