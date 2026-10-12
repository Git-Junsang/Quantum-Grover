#!/usr/bin/env bash
# 플랫폼에 복사한 앱의 baseline_config.h 기본값만 바꿔 release 로 빌드합니다. 저장소 원본은 그대로.
#   build_app.sh <imp폴더> <앱> <매크로=값>...   예) PROFILE=2 CALIB_ITERS=20u
set -euo pipefail
source /opt/rvx/rvx_setup.sh > /dev/null 2>&1
I="$1"; APP="$2"; shift 2
P="$(cd "$I/.." && pwd)"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
C="$P/app/$APP/src/baseline_config.h"
cp "$REPO/software/orca_grover_develop/apps/$APP/src/baseline_config.h" "$C"
for kv in "$@"; do
    k="BBHT_${kv%%=*}"; v="${kv#*=}"
    grep -q "^#define $k " "$C" || { echo "매크로가 없습니다: $k"; exit 1; }
    sed -i "s|^#define $k .*|#define $k $v|" "$C"
done
grep -E "^#define BBHT_(MODEL|PROFILE|SEED_COUNT|CALIB_ITERS|SUBSET_[A-Z_]+) " "$C" | sed 's/^/  /'
cd "$I" && make "$APP" BUILD_MODE=release > "$I/build_$APP.log" 2>&1 || { tail -20 "$I/build_$APP.log"; exit 1; }
grep -q -- "-O2" "$I/build_$APP.log" || { echo "release(-O2) 빌드가 아닙니다"; exit 1; }
ls -la "$I/$APP.sram.hex" | awk '{print "  hex", $5, $6, $7, $8}'
