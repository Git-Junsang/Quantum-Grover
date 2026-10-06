#!/bin/bash
#
# hardware_bram 모델 하나를 RVX 플랫폼에 설치합니다. 모든 모델이 이 스크립트를
# 같이 씁니다.
#
#   install_model.sh <모델폴더> [플랫폼경로]
#
# 보통은 직접 부르지 않고 각 모델의 rvx/install_to_platform.sh 를 부릅니다.
# 그쪽이 모델 폴더와 앱 목록(APPS)을 정해 이 스크립트로 넘깁니다.
#
# 무엇이 어디서 오는가
#
#   hardware_bram/src/          통신 계층 3 · Main IP 10 · grover_param.vh ·
#                               user region   -- 모든 모델 공용
#   hardware_bram/firmware/     드라이버 · 앱 -- 모든 모델 공용
#   <모델>/src/                 bbht_grover_core_adapter.v 하나. 모델마다 다른 것은
#                               이 어댑터의 파라미터 기본값(K·H·E·M)뿐입니다
#   <모델>/rvx/<플랫폼>.xml     플랫폼 정의. 모델 폴더의 xml 이 하나여야 합니다
#
# 플랫폼 경로를 안 주면 $RVX_MINI_HOME/platform/<xml 이름> 으로 갑니다. RVX 는
# 폴더 이름 · XML 이름 · user_region 파일 이름이 서로 같아야 해서, 다른 경로를
# 주면 XML 의 <name> 을 그 폴더 이름으로 바꿔 넣습니다.
#
# 2026-10-06 에 체크포인트 판과 체크포인트 없는 판의 설치 스크립트를 이것 하나로
# 합쳤습니다. 체크포인트 없는 판에서 생긴 두 가지 -- user/rtl 을 비우고 다시
# 채우기, RVX user 뼈대 중 빠진 것 채우기 -- 를 모든 모델이 같이 받습니다.
set -e

if [ -z "$1" ] || [ ! -d "$1/src" ]; then
    echo "사용법: $0 <모델폴더> [플랫폼경로]"
    exit 2
fi

MODEL=$(cd "$1" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
BRAM=$(cd "$HERE/.." && pwd)                 # hardware_bram (공용)
ROOT=$(cd "$BRAM/.." && pwd)                 # 저장소 루트
APPS=${APPS:-bbht_console}

XML=$(ls "$MODEL"/rvx/*.xml 2>/dev/null)
[ "$(echo "$XML" | wc -w)" = 1 ] || { echo "모델 rvx/ 에 xml 이 하나가 아닙니다: $MODEL/rvx"; exit 1; }
XML_NAME=$(basename "$XML" .xml)

PLATFORM=${2:-${RVX_MINI_HOME:-/opt/rvx}/platform/$XML_NAME}
PLATFORM_NAME=$(basename "$PLATFORM")

if [ ! -d "$PLATFORM" ]; then
    echo "플랫폼 디렉터리가 없습니다: $PLATFORM"
    echo "먼저 만드십시오:"
    echo "  mkdir -p $PLATFORM"
    echo "  cp \$RVX_MINI_HOME/platform/tip_hello/Makefile $PLATFORM/"
    exit 1
fi

say() { printf '  %-52s %s\n' "$1" "$2"; }

echo "모델:      $(basename "$MODEL")"
echo "설치 대상: $PLATFORM"

# 1. CSR 정본에서 헤더를 다시 생성합니다. 이 순서를 지켜야 RTL 과 C 가
#    같은 맵을 봅니다.
python3 "$ROOT/software/contract/gen_csr.py" > /dev/null
say "software/contract/generated" "재생성"

# 2. 플랫폼 XML. 첫 <name> 이 플랫폼 이름입니다 (뒤의 <name> 들은 IP 이름).
sed "0,/<name>${XML_NAME}<\/name>/s||<name>${PLATFORM_NAME}</name>|" \
    "$XML" > "$PLATFORM/${PLATFORM_NAME}.xml"
say "${PLATFORM_NAME}.xml" "-> $PLATFORM/"

# 3. 유저 RTL. 생성된 CSR 헤더도 include 경로에 같이 둡니다.
#
#    아래 목록만 옮깁니다. grover_policy_ooc_top.v 와
#    grover_policy_impl_wrapper.v 는 policy OOC 합성 전용이라 플랫폼에
#    들어가면 최상위가 셋이 됩니다. bbht_bram_top.v 도 옮기지 않습니다 --
#    wrapper 와 같은 자리에 들어가는 다른 최상단이라 둘 다 넣으면 최상위가
#    둘이 됩니다. 체크포인트를 끈 모델도 grover_policy.v 와
#    grover_checkpoint.v 를 옮깁니다 -- 정책 엔진과 Planner/Executor 는
#    generate 로 빠지지만 E4 진폭 메모리(grover_ckpt_mem_interleaved_e4)가
#    grover_checkpoint.v 에 있고, 인스턴스되지 않는 모듈은 합성이 버립니다.
CORE_SRC="bbht_grover_main_ip.v \
          grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
          grover_iteration.v grover_loader.v grover_measurement.v \
          grover_memories.v grover_policy.v grover_status.v"

# 앞선 설치(다른 모델일 수도 있습니다)의 흔적이 남지 않게 비우고 다시 채웁니다.
rm -rf "$PLATFORM/user/rtl/src" "$PLATFORM/user/rtl/include"
mkdir -p "$PLATFORM/user/rtl/src" "$PLATFORM/user/rtl/include"
for f in $CORE_SRC; do
    cp "$BRAM/src/$f"                              "$PLATFORM/user/rtl/src/"
done
cp "$BRAM/src/grover_param.vh"                     "$PLATFORM/user/rtl/include/"
cp "$BRAM/src/bbht_rvx_wrapper.v" "$BRAM/src/bbht_grover_mmio.v" \
   "$BRAM/src/bbht_ahb_loader.v"                   "$PLATFORM/user/rtl/src/"
cp "$MODEL/src/bbht_grover_core_adapter.v"         "$PLATFORM/user/rtl/src/"
cp "$BRAM/src/bbht_grover_user_region.vh" \
   "$PLATFORM/user/rtl/include/${PLATFORM_NAME}_user_region.vh"
cp "$ROOT/software/contract/generated/bbht_grover_csr.vh" "$PLATFORM/user/rtl/include/"
say "user/rtl/{src,include}" "통신 계층 3 + 모델 어댑터 + Main IP 10 + 헤더"
# 어떤 구성이 들어갔는지 눈으로 확인할 수 있게 어댑터 기본값을 찍습니다.
grep -E '^\s*parameter integer' "$MODEL/src/bbht_grover_core_adapter.v" \
    | sed -E 's/^\s*parameter integer\s+/      /; s/,$//'

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

# 3c. RVX user 뼈대. RVX 는 make syn 때 user/ 가 **없을 때만** 자기 뼈대
#     ($RVX_DEVKIT/env/user: set_sim_env.mh · set_fpga_{syn,imp}_env.tcl ·
#     sim/include/sim_user_region.vh)를 복사합니다. 이 스크립트가 user/ 를 먼저
#     만들면 그 복사가 건너뛰어져 SoC 시뮬 컴파일이 user region 헤더를 못
#     찾습니다 (2026-09-25 에 이것으로 첫 시뮬이 실패). 빠진 파일만 채웁니다.
SKEL="${RVX_MINI_HOME:-/opt/rvx}/rvx_devkit/env/user"
for f in env/set_sim_env.mh env/set_fpga_syn_env.tcl env/set_fpga_imp_env.tcl \
         sim/include/sim_user_region.vh; do
    if [ ! -f "$PLATFORM/user/$f" ] && [ -f "$SKEL/$f" ]; then
        mkdir -p "$(dirname "$PLATFORM/user/$f")"
        cp "$SKEL/$f" "$PLATFORM/user/$f"
    fi
done
mkdir -p "$PLATFORM/user/sim/src" "$PLATFORM/user/sim/env"
say "user/env · user/sim" "RVX 뼈대 중 빠진 것만 채움"

# 4. 드라이버. 생성된 C 헤더를 같은 폴더에 두면 앱의 compile_list 가
#    '../../user/api' 한 줄로 둘 다 잡습니다.
mkdir -p "$PLATFORM/user/api"
cp "$BRAM/firmware/bbht_grover_driver."{c,h}       "$PLATFORM/user/api/"
cp "$ROOT/software/contract/generated/bbht_grover_regs.h" "$PLATFORM/user/api/"
say "user/api" "driver + regs.h"

# 5. 앱. 앱 폴더를 지우고 다시 복사해 이전 빌드(rtl.debug 등)가 남지 않게 합니다.
mkdir -p "$PLATFORM/app"
for a in $APPS; do
    [ -d "$BRAM/firmware/$a" ] || { echo "앱이 없습니다: firmware/$a"; exit 1; }
    rm -rf "$PLATFORM/app/$a"
    cp -r "$BRAM/firmware/$a"                      "$PLATFORM/app/"
    say "app/$a" "hardware_bram/firmware"
done

echo
echo "다음 단계:"
echo "  cd $PLATFORM"
echo "  make syn                                   # 플랫폼 생성 (user_region 반영)"
echo "  make sim_rtl                               # Questa 시뮬 환경"
echo "  cd sim_rtl && make bbht_console.sim"
echo "  cd $PLATFORM && make imp_fpga TARGET_IMP_CLASS=arty-100t"
echo "  cd imp_arty-100t_<날짜> && make imp         # 합성 · 구현 · 비트스트림"
echo
echo "주의: make syn 이 user/template/ 의 새 template 을 만들 수 있습니다."
echo "      RVX 가 IP 를 추가/제거했다면 template 과 hardware_bram/rvx/"
echo "      bbht_grover_user_region.vh.generated 를 대조해서 배선 이름이"
echo "      바뀌지 않았는지 확인하십시오."
