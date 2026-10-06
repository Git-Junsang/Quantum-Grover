#!/bin/bash
#
# hardware_dram 트리를 RVX 플랫폼 bbht_grover_dram 에 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover_dram 으로 갑니다.
# hardware_bram/rvx/install_model.sh (bram 모델 공용 설치기)와 같은 틀이고 다른 것은 셋입니다.
#
#   1. 플랫폼 XML 이 bbht_grover_dram.xml 입니다. slow_dram(MIG DDR3L)과
#      AXI4 마스터 i_grover_dram 이 더 있고, use_large_ram_manually 로
#      링커가 DRAM 을 안 쓰게 해 두었습니다
#   2. RTL 은 DRAM 갈래 Main IP + 통신 계층 + AXI 브리지이고, 최상단이
#      bbht_dram_axi_top 하나입니다. 계약판 bbht_rvx_wrapper.v 와 어댑터,
#      추상 포트 최상단 하나만 쓰는 회귀용 파일은 옮기지 않습니다
#   3. 펌웨어(드라이버, bbht_console)는 hardware_bram/firmware/ 에서 가져옵니다.
#      CSR 정본이 두 갈래 공통이라 같은 소스가 두 비트스트림 모두에서 돕니다.
#      콘솔은 ID 에서 PLATFORM_NAME 으로 자기가 어느 갈래인지 알립니다
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(cd "$HERE/.." && pwd)        # hardware_dram
ROOT=$(cd "$HW/.." && pwd)       # 저장소 루트
FW="$ROOT/hardware_bram/firmware"

PLATFORM=${1:-${RVX_MINI_HOME:-/opt/rvx}/platform/bbht_grover_dram}
PLATFORM_NAME=$(basename "$PLATFORM")

if [ ! -d "$PLATFORM" ]; then
    echo "플랫폼 디렉터리가 없습니다: $PLATFORM"
    echo "먼저 만드십시오:"
    echo "  mkdir -p $PLATFORM"
    echo "  cp \$RVX_MINI_HOME/platform/tip_hello/Makefile $PLATFORM/"
    exit 1
fi

say() { printf '  %-52s %s\n' "$1" "$2"; }

echo "설치 대상: $PLATFORM"

# 1. CSR 정본 헤더 재생성
python3 "$ROOT/software/contract/gen_csr.py" > /dev/null
say "software/contract/generated" "재생성"

# 2. 플랫폼 XML
sed "s|<name>bbht_grover_dram</name>|<name>${PLATFORM_NAME}</name>|" \
    "$HERE/bbht_grover_dram.xml" > "$PLATFORM/${PLATFORM_NAME}.xml"
say "${PLATFORM_NAME}.xml" "-> $PLATFORM/"

# 3. 유저 RTL. sim/Makefile 의 DRAM_CORE 와 같은 목록에 통신 계층과 브리지,
#    최상단을 더합니다. glob 을 쓰지 않습니다 -- src/ 에는 최상위 후보가
#    셋(bbht_dram_top, bbht_dram_axi_top, 계약판 bbht_rvx_wrapper) 있습니다.
#    bbht_dram_top 은 bbht_dram_axi_top 안에 들어가므로 같이 옮깁니다.
RTL="lpsoc_bbht_grover_main_ip.v grover_arithmetic.v grover_dram_random.v \
     grover_dram_amp_store.v grover_dram_prep_seq.v grover_dram_queue.v \
     grover_dram_shot_fsm.v grover_iteration.v grover_loader.v \
     grover_measurement.v grover_memories.v grover_status.v \
     bbht_grover_mmio.v bbht_ahb_loader.v bbht_dram_top.v \
     grover_dram_axi_bridge.v bbht_dram_axi_top.v"

rm -rf "$PLATFORM/user/rtl/src"
mkdir -p "$PLATFORM/user/rtl/src" "$PLATFORM/user/rtl/include"
for f in $RTL; do
    cp "$HW/src/$f"                                   "$PLATFORM/user/rtl/src/"
done
cp "$HW/src/grover_param.vh" "$HW/src/grover_dram_param.vh" "$PLATFORM/user/rtl/include/"
cp "$ROOT/software/contract/generated/bbht_grover_csr.vh"  "$PLATFORM/user/rtl/include/"
cp "$HW/src/bbht_grover_user_region.vh" \
   "$PLATFORM/user/rtl/include/${PLATFORM_NAME}_user_region.vh"
say "user/rtl/{src,include}" "DRAM Main IP 12 + 통신 계층 3 + 브리지 + 최상단"

# 3b. 사용자 RTL 등록 (bram 쪽과 같은 이유. set_fpga_syn_env.tcl 이 source 함)
mkdir -p "$PLATFORM/user/env"
cat > "$PLATFORM/user/env/set_rtl_syn_env.tcl" <<'TCL'
set verilog_module_list [concat_file_list $verilog_module_list ${PLATFORM_DIR}/user/rtl/src/*.v]
set verilog_module_list [concat_file_list $verilog_module_list ${PLATFORM_DIR}/user/rtl/src/*.sv]
lappend verilog_include_list ${PLATFORM_DIR}/user/rtl/include
TCL
say "user/env/set_rtl_syn_env.tcl" "user/rtl 을 합성 경로에 등록"

# 3c. 배치/배선 순서. RVX 가 NoC 를 MIG ui_clk(150 MHz)로 돌려서 기본 흐름으로는
#     NoC 안 경로가 -0.66 ns 모자랍니다. 자세한 이유는 파일 머리말.
mkdir -p "$PLATFORM/user/fpga/arty-100t"
cp "$HERE/pnr_manually.tcl" "$PLATFORM/user/fpga/arty-100t/pnr_manually.tcl"
say "user/fpga/arty-100t/pnr_manually.tcl" "타이밍 우선 배치/배선"

# 4. 드라이버
mkdir -p "$PLATFORM/user/api"
cp "$FW/bbht_grover_driver."{c,h}                          "$PLATFORM/user/api/"
cp "$ROOT/software/contract/generated/bbht_grover_regs.h"  "$PLATFORM/user/api/"
say "user/api" "driver + regs.h (hardware_bram/firmware)"

# 5. 앱. 콘솔만 옮깁니다. bbht_paper_bench 와 orca_sw_baseline 은 보드
#    정본(bram)의 실측을 낸 앱이라 이 갈래에는 두지 않습니다.
mkdir -p "$PLATFORM/app"
rm -rf "$PLATFORM/app/bbht_console"
cp -r "$FW/bbht_console"                                   "$PLATFORM/app/"
say "app/bbht_console" "UART 명령 셸 (hardware_bram/firmware)"

echo
echo "다음 단계:"
echo "  cd $PLATFORM"
echo "  make syn                     # 플랫폼 생성 (user_region 반영)"
echo "  make sim_rtl                 # Questa 시뮬 환경"
echo "  cd sim_rtl && BBHT_SCRIPT=script_predicate500_dram.h make bbht_console.sim"
echo "  cd $PLATFORM && make imp_fpga    # arty-100t 비트스트림"
echo
echo "주의: RTL 시뮬의 DDR 모델은 2 MiB 입니다(SIM_LARGE_RAM_SIZE, spec 으로 못 바꿈)."
echo "      슬롯 j 가 43 을 넘는 탐색은 SoC 시뮬에서 돌리지 마십시오. 보드는 256 MiB 입니다."
