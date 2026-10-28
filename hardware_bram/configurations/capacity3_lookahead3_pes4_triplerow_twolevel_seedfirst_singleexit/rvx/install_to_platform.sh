#!/bin/bash
#
# K3/H3-E4-M3-S6 모델(M3 + seed-first 정책 탐색)을 별도 RVX 플랫폼에
# 설치합니다. 기존 M2 정본과 M3 플랫폼을 덮어쓰지 않습니다.
#
#   ./install_to_platform.sh [플랫폼경로]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
APPS="bbht_console bbht_paper_bench orca_sw_baseline" \
    exec "$HERE/../../../rvx/install_model.sh" "$HERE/.." "$@"
