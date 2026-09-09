#!/bin/bash
#
# hardware_bram 트리를 RVX 플랫폼에 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover_upgrade 로 갑니다.
# 플랫폼 이름은 2026-09-07 보드 최종 빌드와 맞춘 것입니다 -- RVX 는 폴더
# 이름·XML 이름·user_region 파일 이름이 서로 같아야 합니다.
#
# PJK 인수인계 §4.2 는 "RVX global tool 쪽 수정분을 source tree 밖의 임시
# 수정으로 두지 말고 재현 가능하게 관리" 하라고 요청합니다. 이 스크립트가
# 그 답입니다 -- 무엇을 어디에 넣는지가 전부 여기 적혀 있고, 저장소에서
# 플랫폼으로 가는 방향만 있으므로 되돌리기도 쉽습니다.
#
# 통신 계층이 두 벌이라 LAYER 로 고릅니다 (아래 3번).
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(cd "$HERE/.." && pwd)      # hardware_bram
ROOT=$(cd "$HW/.." && pwd)     # 저장소 루트

PLATFORM=${1:-${RVX_MINI_HOME:-/opt/rvx}/platform/bbht_grover_upgrade}
PLATFORM_NAME=$(basename "$PLATFORM")

if [ ! -d "$PLATFORM" ]; then
    echo "플랫폼 디렉터리가 없습니다: $PLATFORM"
    echo "먼저 만드십시오:"
    echo "  mkdir -p $PLATFORM"
    echo "  cp \$RVX_MINI_HOME/platform/tip_hello/Makefile $PLATFORM/"
    exit 1
fi

say() { printf '  %-52s %s\n' "$1" "$2"; }

# LAYER=final (기본)  보드 정본 통째. src/ 의 wrapper·mmio·loader·Main IP
# LAYER=comm          우리 통신 계층(src_comm/) + 어댑터 + src/ 의 Main IP
#
# 둘 다 module bbht_rvx_wrapper 를 정의하므로 한쪽만 설치해야 합니다.
LAYER=${LAYER:-final}
case "$LAYER" in
    final|comm) ;;
    *) echo "LAYER 는 final 또는 comm 이어야 합니다 (받은 값: $LAYER)" >&2; exit 1 ;;
esac

echo "설치 대상: $PLATFORM  (LAYER=$LAYER)"

# 1. CSR 정본에서 헤더를 다시 생성합니다. 이 순서를 지켜야 RTL 과 C 가
#    같은 맵을 봅니다. 정본 mmio 는 이 헤더를 include 하지 않고 같은 값을
#    직접 적고 있지만, 드라이버와 comm 갈래가 이 헤더를 씁니다.
python3 "$ROOT/software/csr/gen_csr.py" > /dev/null
say "software/csr/generated" "재생성"

# 2. 플랫폼 XML. 폴더 이름과 <name> 이 같아야 하므로 필요하면 바꿔 넣습니다.
mkdir -p "$PLATFORM"
sed "s|<name>bbht_grover_upgrade</name>|<name>${PLATFORM_NAME}</name>|" \
    "$HERE/bbht_grover_upgrade.xml" > "$PLATFORM/${PLATFORM_NAME}.xml"
say "${PLATFORM_NAME}.xml" "-> $PLATFORM/"

# 3. 유저 RTL. 생성된 CSR 헤더도 include 경로에 같이 둡니다.
#
#    src/       보드 정본 (freeze. 고치지 마십시오)
#    src_comm/  우리 통신 계층 + 어댑터 (고쳐도 됩니다)
#
#    아래 목록만 옮깁니다. grover_policy_ooc_top.v 와
#    grover_policy_impl_wrapper.v 는 policy OOC 합성 전용이라 플랫폼에
#    들어가면 최상위가 셋이 됩니다.
CORE_SRC="bbht_grover_main_ip.v \
          grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
          grover_iteration.v grover_loader.v grover_measurement.v \
          grover_memories.v grover_policy.v grover_status.v"

mkdir -p "$PLATFORM/user/rtl/src" "$PLATFORM/user/rtl/include"
for f in $CORE_SRC; do
    cp "$HW/src/$f"                               "$PLATFORM/user/rtl/src/"
done
cp "$HW/src/grover_param.vh"                      "$PLATFORM/user/rtl/include/"

if [ "$LAYER" = "final" ]; then
    cp "$HW/src/bbht_rvx_wrapper.v" "$HW/src/bbht_grover_mmio.v" \
       "$HW/src/bbht_ahb_loader.v"                "$PLATFORM/user/rtl/src/"
    cp "$HW/src/bbht_grover_upgrade_user_region.vh" \
       "$PLATFORM/user/rtl/include/${PLATFORM_NAME}_user_region.vh"
    say "user/rtl/{src,include}" "정본 통신 계층 3 + Main IP 10 + 헤더"
else
    cp "$HW/src_comm/bbht_rvx_wrapper.v" "$HW/src_comm/bbht_grover_mmio.v" \
       "$HW/src_comm/bbht_ahb_loader.v" \
       "$HW/src_comm/bbht_grover_core_adapter.v"  "$PLATFORM/user/rtl/src/"
    cp "$HW/src_comm/bbht_grover_user_region.vh" \
       "$PLATFORM/user/rtl/include/${PLATFORM_NAME}_user_region.vh"
    say "user/rtl/{src,include}" "우리 통신 계층 3 + 어댑터 + Main IP 10 + 헤더"
fi
cp "$ROOT/software/csr/generated/bbht_grover_csr.vh" "$PLATFORM/user/rtl/include/"

# 3b. 사용자 RTL 등록. imp 쪽 set_fpga_syn_env.tcl 이 이 파일을 source 해서
#     user/rtl/{src,include} 를 Vivado 프로젝트에 넣습니다. 이게 없으면
#     합성이 user_region 헤더를 못 찾고 elaboration 에서 죽습니다
#     (2026-09-06 에 이걸로 make imp 가 4건 오류로 실패했습니다).
mkdir -p "$PLATFORM/user/env"
cat > "$PLATFORM/user/env/set_rtl_syn_env.tcl" <<'TCL'
set verilog_module_list [concat_file_list $verilog_module_list ${PLATFORM_DIR}/user/rtl/src/*.v]
set verilog_module_list [concat_file_list $verilog_module_list ${PLATFORM_DIR}/user/rtl/src/*.sv]
lappend verilog_include_list ${PLATFORM_DIR}/user/rtl/include
TCL
say "user/env/set_rtl_syn_env.tcl" "user/rtl 을 합성 경로에 등록"

# 4. 드라이버. 생성된 C 헤더를 같은 폴더에 두면 앱의 compile_list 가
#    '../../user/api' 한 줄로 둘 다 잡습니다.
mkdir -p "$PLATFORM/user/api"
cp "$HW/firmware/bbht_grover_driver."{c,h}        "$PLATFORM/user/api/"
cp "$ROOT/software/csr/generated/bbht_grover_regs.h" "$PLATFORM/user/api/"
say "user/api" "driver + regs.h"

# 5. 앱
mkdir -p "$PLATFORM/app"
cp -r "$HW/firmware/bbht_console"                 "$PLATFORM/app/"
say "app/bbht_console" "UART 명령 셸"
# 500런 실시간 벤치. 보드 실측(2026-09-08 묶음)을 낸 앱입니다. 시드 로스터
# 100개가 안에 들어 있고 RVX 실시간 클럭으로 마이크로초를 잽니다.
cp -r "$HW/firmware/bbht_paper_bench"             "$PLATFORM/app/"
say "app/bbht_paper_bench" "실시간 벤치 (M=1/4/16/64/256 x 시드 100)"
# 가속기를 안 쓰는 ORCA 1코어 기준선. 같은 워크로드를 소프트웨어로만 돕니다.
cp -r "$HW/firmware/orca_sw_baseline"             "$PLATFORM/app/"
say "app/orca_sw_baseline" "ORCA 순수 소프트웨어 기준선"

echo
echo "다음 단계:"
echo "  cd $PLATFORM"
echo "  make syn                     # 플랫폼 생성 (user_region 반영)"
echo "  make sim_rtl                 # Questa 시뮬 환경"
echo "  cd sim_rtl && make bbht_console.sim"
echo "  cd $PLATFORM && make arty-100t"
echo
echo "주의: make syn 이 user/template/ 의 새 template 을 만들 수 있습니다."
echo "      RVX 가 IP 를 추가/제거했다면 template 과 우리 user_region 을"
echo "      대조해서 배선 이름이 바뀌지 않았는지 확인하십시오."
