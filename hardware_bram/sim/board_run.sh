#!/usr/bin/env bash
#
# 원격 200T 보드(AX7A200B, sdsl-fpga)에서 한 모델 · 한 앱을 잽니다.
#
#   hardware_bram/sim/board_run.sh <모델> [앱] [제한초]
#
#   모델   models/ 아래 폴더 이름에서 hardware_bram_ 을 뗀 것 (예 K3H3_E4_M2)
#   앱     기본 bbht_paper_bench. orca_sw_baseline 은 K3H3_E4_M2 에만 설치돼 있습니다
#          predicate500 을 주면 bbht_console 을 올리고 원격에서 software/host/bbht_predicate500.py
#          (네 술어 x 500 x 두 모드)를 돌립니다. 이때 제한초는 호스트 도구 전체 시간 상한입니다
#   제한초 UART 캡처 시간 제한. 기본 600 (paper_bench 는 15초 안팎, ORCA 기준선은 2시간쯤)
#
# 먼저 되어 있어야 하는 것
#   - 모델 설치와 200T 구현: rvx/install_to_platform.sh 뒤 /fpga-syn-rvx --budget-100t
#     (구현 폴더는 그 스킬이 남기는 플랫폼의 .fpga_syn_rvx_last 로 찾습니다)
#   - 앱 hex: 구현 폴더에서 make <앱>
#   - 원격 접속: /fpga-flash 스킬의 check 가 통과하는 상태
#
# 하는 일
#   1) OCD 묶음을 만듭니다. imp 폴더의 set_ocd_env.tcl 은 /opt/rvx 절대경로를 읽어 원격에서
#      못 쓰므로, 필요한 tcl 을 묶음 안 상대경로로 모읍니다(기술문서 17장 17.4절과 같은 방식).
#      메모리맵(arch/)은 플랫폼마다 생성되므로 그 모델의 플랫폼에서 가져옵니다.
#   2) 비트스트림을 굽습니다 (fpga-flash 스킬의 sdsl_fpga.sh program).
#   3) 원격에서 UART 캡처를 먼저 띄우고, OpenOCD 로 앱을 SRAM 에 올린 뒤 붙여 둔 채 기다립니다.
#      OpenOCD 를 내리면 어댑터가 플랫폼을 리셋해 앱이 사라지므로 캡처가 끝날 때까지 둡니다.
#   4) 로그를 가져오고, paper_bench 면 board_vs_bench500.py 로 bench500 과 맞댑니다.
#
# 원상 복구(sdsl_fpga.sh restore --pcie)는 하지 않습니다. 보드 플래시에는 다른 사람의 PCIe
# 설계가 있으니 측정을 다 마친 뒤 반드시 따로 돌리십시오.
#
# 환경변수
#   BOARD_WORK   결과를 둘 곳 (기본 /tmp/bbht_board)
#   BOARD_UART   원격 UART 포트 (기본: /dev/serial/by-id 의 CP2102N)
set -euo pipefail

MODEL="${1:?모델 이름을 주십시오 (예 K3H3_E4_M2)}"
APP="${2:-bbht_paper_bench}"
LIMIT="${3:-600}"

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MODEL_DIR="$REPO/hardware_bram/models/hardware_bram_$MODEL"
FLASH="$REPO/.claude/skills/fpga-flash/scripts/sdsl_fpga.sh"
[[ -d "$MODEL_DIR" ]] || { echo "모델이 없습니다: $MODEL"; exit 1; }
[[ -x "$FLASH" ]] || { echo "fpga-flash 스킬 스크립트가 없습니다: $FLASH"; exit 1; }

[[ -n "${RVX_MINI_HOME:-}" ]] || source /opt/rvx/rvx_setup.sh > /dev/null
# 플랫폼 이름은 모델 xml 의 첫 <name> 입니다 (RVX 는 폴더 · xml · user_region 이름이 같아야 함)
PLAT="$(grep -m1 -o '<name>[^<]*</name>' "$MODEL_DIR"/rvx/*.xml | sed 's/<[^>]*>//g')"
P="$RVX_MINI_HOME/platform/$PLAT"
[[ -f "$P/.fpga_syn_rvx_last" ]] || { echo "200T 구현 기록이 없습니다: $P (/fpga-syn-rvx 먼저)"; exit 1; }
I="$(cat "$P/.fpga_syn_rvx_last")"
BIT="$(ls "$I"/imp_result/*.ax7a200b.bit)"
# predicate500 은 앱이 아니라 "콘솔 + 원격 호스트 도구" 측정 방식입니다.
LOAD_APP="$APP"; [[ "$APP" == "predicate500" ]] && LOAD_APP=bbht_console
HEX="$I/$LOAD_APP.sram.hex"
[[ -f "$HEX" ]] || { echo "앱 hex 가 없습니다: $HEX (구현 폴더에서 make $LOAD_APP)"; exit 1; }

TS="$(date +%Y-%m-%d_%H%M%S)"
WORK="${BOARD_WORK:-/tmp/bbht_board}/${TS}_${MODEL}_${APP}"
PKG="$WORK/pkg"
REMOTE="sdsl_fpga_runs/${TS}_${PLAT}_${APP}"

# ---------------------------------------------------------------- 1) OCD 묶음
mkdir -p "$PKG/rvx_env" "$PKG/arch"
cp "$I/ax7a200b.cfg" "$I/run_$LOAD_APP.tcl" "$HEX" "$PKG/"
cp /opt/rvx/local_setup/ocd/openocd_rvp "$PKG/"
for f in ervp_jtag_memorymap_offset ervp_platform_controller_memorymap_offset \
         ervp_external_peri_group_memorymap_offset munoc_memorymap_offset \
         util jtag_function memory_function control_function mmio_function \
         misc_api platform_controller_api flash_api noc_api dump_api; do
    cp "/opt/rvx/rvx_devkit/env/ocd/$f.tcl" "$PKG/rvx_env/"
done
cp "$P"/arch/tcl/{memorymap_info,hw_info,ssw_info}.tcl "$PKG/arch/"
cat > "$PKG/set_ocd_env.tcl" <<'EOF'
# imp 폴더의 set_ocd_env.tcl 을 이 묶음 안 상대경로로 옮긴 것 (원본은 /opt/rvx 절대경로)
foreach f {ervp_jtag_memorymap_offset ervp_platform_controller_memorymap_offset
           ervp_external_peri_group_memorymap_offset munoc_memorymap_offset} {
  source ./rvx_env/$f.tcl
}
source ./arch/memorymap_info.tcl
source ./arch/hw_info.tcl
source ./arch/ssw_info.tcl
foreach f {util jtag_function memory_function control_function mmio_function
           misc_api platform_controller_api flash_api noc_api dump_api} {
  source ./rvx_env/$f.tcl
}
print_platform_info
EOF
cp "$HERE/uart_capture.py" "$PKG/"
(cd "$(dirname "$BIT")" && sha256sum "$(basename "$BIT")") > "$PKG/sha256.txt"
(cd "$I" && sha256sum "$LOAD_APP.sram.hex") >> "$PKG/sha256.txt"
if [[ "$APP" == "predicate500" ]]; then
    # 호스트 도구가 저장소 상대경로(_REPO)로 기댓값과 생성 헤더를 찾으므로 그 모양을 그대로 만듭니다.
    mkdir -p "$PKG/repo/software/host" "$PKG/repo/software/contract/generated" \
             "$PKG/repo/software/experiments/predicate500_benchmark/expected"
    cp "$REPO"/software/host/{bbht_cli.py,bbht_predicate500.py} "$PKG/repo/software/host/"
    # 폴더(__pycache__ 등)는 빼고 파일만 옮깁니다.
    find "$REPO"/software/contract/generated -maxdepth 1 -type f -exec cp {} "$PKG/repo/software/contract/generated/" \;
    cp "$REPO"/software/experiments/predicate500_benchmark/expected/*.csv \
       "$PKG/repo/software/experiments/predicate500_benchmark/expected/"
fi

echo "[1] 묶음 전송 -> sdsl-fpga:~/$REMOTE"
ssh sdsl-fpga "mkdir -p ~/$REMOTE"
scp -q -r "$PKG"/. "sdsl-fpga:$REMOTE/"

# ---------------------------------------------------------------- 2) 굽기
echo "[2] 굽기 $(basename "$BIT")"
"$FLASH" program "$BIT" | tail -2

# ---------------------------------------------------------------- 3) 캡처 + 앱 적재
UART="${BOARD_UART:-}"
if [[ -z "$UART" ]]; then
    UART="$(ssh sdsl-fpga 'ls /dev/serial/by-id/*CP2102N* 2>/dev/null | head -1')"
    [[ -n "$UART" ]] || { echo "원격에 CP2102N UART 가 없습니다. BOARD_UART 로 지정하십시오"; exit 1; }
fi
if [[ "$APP" == "predicate500" ]]; then
echo "[3] 콘솔 적재 + 네 술어 측정 ($UART)"
# OpenOCD 로 콘솔을 올려 붙여 둔 채, 같은 원격에서 호스트 도구가 UART 로 명령을 보냅니다.
# 도구가 끝나면(또는 제한초) OpenOCD 를 내립니다. 결과 CSV 는 실행마다 바로 써져 끊겨도 남습니다.
ssh sdsl-fpga "cd ~/$REMOTE || exit 1; chmod +x openocd_rvp; \
  sudo ./openocd_rvp -f ax7a200b.cfg -c 'source run_bbht_console.tcl' > ocd.log 2>&1 & \
  sleep 8; \
  sudo timeout $LIMIT python3 repo/software/host/bbht_predicate500.py --port '$UART' \
       --out predicate500.xlsx --log uart.log --quiet > host.out 2>&1; echo \$? > host.rc; \
  sudo pkill -f '^\./openocd_rvp ' 2>/dev/null; sleep 1; \
  echo \"  host_rc=\$(cat host.rc) (0 = 전부 일치)\"; tail -16 host.out"
scp -q "sdsl-fpga:$REMOTE/predicate500.csv" "sdsl-fpga:$REMOTE/host.out" "sdsl-fpga:$REMOTE/uart.log" \
    "sdsl-fpga:$REMOTE/ocd.log" "sdsl-fpga:$REMOTE/sha256.txt" "$WORK/"
echo "[4] 결과 $WORK"
echo "측정을 다 마쳤으면: $FLASH restore --pcie"
exit 0
fi
echo "[3] UART 캡처($UART) + 앱 적재 ($APP)"
# cd 는 따로 끝냅니다. "cd && ... &" 로 묶으면 cd 가 백그라운드 서브셸에만 걸려 OpenOCD 가
# 홈 폴더에서 돌고 대기 루프가 끝나지 않습니다(2026-10-08 첫 시도).
# OpenOCD 를 내릴 때 pkill 패턴은 명령줄 머리("./openocd_rvp ")에 고정합니다. 패턴이 이 원격
# 셸의 명령줄에도 들어 있으면 셸까지 죽어 ssh 가 실패로 끝납니다.
ssh sdsl-fpga "cd ~/$REMOTE || exit 1; chmod +x openocd_rvp; \
  (sudo python3 uart_capture.py '$UART' uart.log $LIMIT; echo \$? > capture.rc) > capture.out 2>&1 & \
  sleep 2; \
  sudo ./openocd_rvp -f ax7a200b.cfg -c 'source run_$APP.tcl' > ocd.log 2>&1 & \
  while [ ! -f capture.rc ]; do sleep 2; done; \
  sudo pkill -f '^\./openocd_rvp ' 2>/dev/null; sleep 1; \
  echo \"  capture_rc=\$(cat capture.rc) (0 = 끝 표시를 봄, 2 = 시간 제한)\""

# ---------------------------------------------------------------- 4) 회수 · 대조
scp -q "sdsl-fpga:$REMOTE/uart.log" "sdsl-fpga:$REMOTE/ocd.log" "sdsl-fpga:$REMOTE/sha256.txt" "$WORK/"
echo "[4] 결과 $WORK"
grep -E "BENCHMARK (PASS|FAIL)|^\[RVX/END\]|capture (end|timeout)" "$WORK/uart.log" | sed 's/^/  /' || true
if [[ "$APP" == "bbht_paper_bench" ]]; then
    python3 "$HERE/board_vs_bench500.py" "$WORK/uart.log" --model "$MODEL" --strict-cycles || true
fi
echo "측정을 다 마쳤으면: $FLASH restore --pcie"
