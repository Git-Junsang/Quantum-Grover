#!/bin/bash
#
# 드라이버 + RTL 공동 시뮬레이션.
#
# 실제 펌웨어가 쓰는 bbht_grover_driver.c 를 그대로 컴파일해 verilator 모델에
# 붙입니다. CSR 접근은 BBHT_HOST_TEST 갈래로 bbht_host_rd/wr 에 연결됩니다.
#
# 소스를 /tmp 로 옮겨 놓고 빌드하는 이유가 둘입니다.
#   1. 이 저장소 경로에 공백("중앙대학교 학부인턴")이 있어서 GNU Make 가
#      verilator 생성 makefile 을 그 자리에서 돌리지 못합니다
#   2. verilator 가 -CFLAGS 를 공백으로 쪼개므로 -I 경로에도 공백이 있으면 안 됩니다
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:-/tmp/sjs_drv}

rm -rf "$BUILD"
mkdir -p "$BUILD/src"

# CORE=stub   우리 통신 계층 + 자리 채우개 (기본). 통신 계약만 몇 초에 확인합니다
# CORE=real   우리 통신 계층 + 어댑터 + 정본 Main IP
# CORE=final  보드 정본 통째 (src/ 의 wrapper·mmio·loader·Main IP)
CORE=${CORE:-stub}

# 정본 Main IP 중 합성 경로에 들어가는 열입니다. glob 을 쓰면 policy OOC
# 전용 파일까지 딸려 와서 최상위가 둘이 됩니다.
CORE_FILES="bbht_grover_main_ip.v \
            grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
            grover_iteration.v grover_loader.v grover_measurement.v \
            grover_memories.v grover_policy.v grover_status.v"

cp "$HERE/../testbench/tb_driver.cpp" "$BUILD/src/"

case "$CORE" in
    final)
        # 통신 계층까지 정본. 어댑터가 끼지 않습니다.
        cp "$HERE/../src/bbht_rvx_wrapper.v"   "$BUILD/src/"
        cp "$HERE/../src/bbht_grover_mmio.v"   "$BUILD/src/"
        cp "$HERE/../src/bbht_ahb_loader.v"    "$BUILD/src/"
        cp "$HERE/../src/grover_param.vh"      "$BUILD/src/"
        CORE_SRC=""
        for f in $CORE_FILES; do
            cp "$HERE/../src/$f" "$BUILD/src/"
            CORE_SRC="$CORE_SRC $BUILD/src/$f"
        done
        ;;
    real)
        # 우리 통신 계층 + 어댑터 + 정본 Main IP.
        cp "$HERE/../src_comm/bbht_"*.v        "$BUILD/src/"
        cp "$HERE/../src/grover_param.vh"      "$BUILD/src/"
        CORE_SRC="$BUILD/src/bbht_grover_core_adapter.v"
        for f in $CORE_FILES; do
            cp "$HERE/../src/$f" "$BUILD/src/"
            CORE_SRC="$CORE_SRC $BUILD/src/$f"
        done
        ;;
    *)
        cp "$HERE/../src_comm/bbht_"*.v        "$BUILD/src/"
        rm -f "$BUILD/src/bbht_grover_core_adapter.v"
        cp "$HERE/../testbench/bbht_grover_core_stub.v" "$BUILD/src/"
        CORE_SRC="$BUILD/src/bbht_grover_core_stub.v"
        ;;
esac

cp "$HERE/../../software/csr/generated/bbht_grover_csr.vh" "$BUILD/src/"
cp "$HERE/../../software/csr/generated/bbht_grover_regs.h" "$BUILD/src/"
cp "$HERE/../firmware/bbht_grover_driver."{c,h}    "$BUILD/src/"

# 실물은 탐색 한 번이 수십만 사이클이라 드라이버 폴링 상한을 크게 잡습니다.
if [ "$CORE" = "stub" ]; then
    DRV_TIMEOUT=100000
else
    DRV_TIMEOUT=20000000
fi
DEFS="-DBBHT_HOST_TEST -DBBHT_NO_PRINTF -DBBHT_TIMEOUT=$DRV_TIMEOUT"

# 드라이버는 C 로 따로 컴파일합니다. verilator 의 --exe 는 .cpp 만 규칙을
# 만들어 주므로 오브젝트로 넘기는 편이 확실합니다.
gcc -c -O2 -Wall -Wextra $DEFS -I"$BUILD/src" \
    "$BUILD/src/bbht_grover_driver.c" -o "$BUILD/driver.o"

verilator --cc --exe --build -Wno-fatal -Wno-DECLFILENAME \
    --Mdir "$BUILD/obj" \
    -CFLAGS "$DEFS -I$BUILD/src -Wall" \
    -LDFLAGS "$BUILD/driver.o" \
    -I"$BUILD/src" \
    "$BUILD/src/bbht_rvx_wrapper.v" \
    "$BUILD/src/bbht_grover_mmio.v" \
    "$BUILD/src/bbht_ahb_loader.v" \
    $CORE_SRC \
    --top-module bbht_rvx_wrapper \
    "$BUILD/src/tb_driver.cpp" \
    -o sim_drv > "$BUILD/build.log" 2>&1 || { tail -20 "$BUILD/build.log"; exit 1; }

exec "$BUILD/obj/sim_drv"
