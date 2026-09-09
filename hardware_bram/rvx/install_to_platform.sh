#!/bin/bash
#
# hardware_bram 트리의 통신 계층을 RVX 플랫폼에 설치합니다.
#
#   ./install_to_platform.sh [플랫폼경로]
#
# 인자를 안 주면 $RVX_MINI_HOME/platform/bbht_grover 로 갑니다.
#
# PJK 인수인계 §4.2 는 "RVX global tool 쪽 수정분을 source tree 밖의 임시
# 수정으로 두지 말고 재현 가능하게 관리" 하라고 요청합니다. 이 스크립트가
# 그 답입니다 -- 무엇을 어디에 넣는지가 전부 여기 적혀 있고, 저장소에서
# 플랫폼으로 가는 방향만 있으므로 되돌리기도 쉽습니다.
#
# Main IP 도 함께 옮깁니다. 실물이 2026-09-05 에 src_v2/ 로 들어왔고,
# CORE=v2|v3 로 어느 코어를 설치할지 고릅니다 (아래 3번).
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
HW=$(cd "$HERE/.." && pwd)      # hardware_bram
ROOT=$(cd "$HW/.." && pwd)     # 저장소 루트

PLATFORM=${1:-${RVX_MINI_HOME:-/opt/rvx}/platform/bbht_grover}

if [ ! -d "$PLATFORM" ]; then
    echo "플랫폼 디렉터리가 없습니다: $PLATFORM"
    echo "먼저 만드십시오:"
    echo "  mkdir -p $PLATFORM"
    echo "  cp \$RVX_MINI_HOME/platform/tip_hello/Makefile $PLATFORM/"
    exit 1
fi

say() { printf '  %-52s %s\n' "$1" "$2"; }

echo "설치 대상: $PLATFORM"

# 1. CSR 정본에서 헤더를 다시 생성합니다. 이 순서를 지켜야 RTL 과 C 가
#    같은 맵을 봅니다.
python3 "$ROOT/software/csr/gen_csr.py" > /dev/null
say "software/csr/generated" "재생성"

# 2. 플랫폼 XML
mkdir -p "$PLATFORM"
cp "$HERE/bbht_grover.xml" "$PLATFORM/bbht_grover.xml"
say "bbht_grover.xml" "-> $PLATFORM/"

# 3. 유저 RTL. 생성된 CSR 헤더도 include 경로에 같이 둡니다.
#
#    src/       통신 계층 + 어댑터 (우리가 소유. 고쳐도 됩니다)
#    src_v2/    실물 Main IP (PJK freeze. 고치지 마십시오)
#    src_v3/    src_v2 포크 + PASS2 융합. 측정 경로만 다릅니다
#
#    CORE=v2 (기본) 또는 CORE=v3 으로 고릅니다. 어댑터가 둘 다
#    module bbht_grover_core 를 정의하므로 한쪽만 옮겨야 합니다.
#
#    아래 목록만 옮깁니다. timing_wrapper 와 policy_ooc_top 은 standalone
#    타이밍 증명 전용이라 플랫폼에 들어가면 최상위가 둘이 됩니다.
CORE=${CORE:-v2}
case "$CORE" in
    v2) CORE_DIR="src_v2"; CORE_ADAPTER="bbht_grover_core_adapter.v" ;;
    v3) CORE_DIR="src_v3"; CORE_ADAPTER="bbht_grover_core_adapter_v3.v" ;;
    *)  echo "CORE 는 v2 또는 v3 이어야 합니다 (받은 값: $CORE)" >&2; exit 1 ;;
esac

MAIN_IP_SRC="lpsoc_bbht_grover_main_ip.v \
             grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
             grover_iteration.v grover_loader.v grover_measurement.v \
             grover_memories.v grover_policy.v grover_status.v"

mkdir -p "$PLATFORM/user/rtl/src" "$PLATFORM/user/rtl/include"
# 어댑터는 고른 것 하나만. 나머지 통신 계층 파일은 전부 옮깁니다.
for f in "$HW/src/bbht_"*.v; do
    case "$(basename "$f")" in
        bbht_grover_core_adapter*.v) continue ;;
    esac
    cp "$f"                                       "$PLATFORM/user/rtl/src/"
done
cp "$HW/src/$CORE_ADAPTER"                        "$PLATFORM/user/rtl/src/"
for f in $MAIN_IP_SRC; do
    cp "$HW/$CORE_DIR/$f"                         "$PLATFORM/user/rtl/src/"
done
cp "$HW/src/bbht_grover_user_region.vh"           "$PLATFORM/user/rtl/include/"
cp "$HW/$CORE_DIR/grover_param.vh"                "$PLATFORM/user/rtl/include/"
cp "$ROOT/software/csr/generated/bbht_grover_csr.vh" "$PLATFORM/user/rtl/include/"
say "user/rtl/{src,include}" "wrapper + mmio + loader + $CORE_ADAPTER + $CORE_DIR 10개 + 헤더 2개"

# 3b. 사용자 RTL 등록. imp 쪽 set_fpga_syn_env.tcl 이 이 파일을 source 해서
#     user/rtl/{src,include} 를 Vivado 프로젝트에 넣습니다. 이게 없으면
#     합성이 bbht_grover_user_region.vh 를 못 찾고 elaboration 에서 죽습니다
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
# 250쌍 자동 벤치. 보드 실측을 시뮬(sim/bench250_report.py)과 같은 워크로드로
# 재현하는 앱입니다. 시드 로스터 50개와 참조 데이터셋이 안에 들어 있습니다.
cp -r "$HW/firmware/bbht_paper_bench"             "$PLATFORM/app/"
say "app/bbht_paper_bench" "250쌍 자동 벤치 (M=1/4/16/64/256 x 시드 50)"

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
