#!/usr/bin/env bash
#
# ORCA SW 기준선 앱을 원격 200T 보드(sdsl-fpga)에서 잽니다. hardware_bram/sim/board_run.sh 와
# 같은 순서(OCD 묶음 -> 굽기 -> UART 캡처 먼저 -> OpenOCD 로 앱 적재)이고, 다른 점은 원격
# 쪽을 setsid 로 떼어 놓아 ssh 가 끊겨도 측정이 계속된다는 것 하나입니다(FULL 은 몇 시간).
#
#   board_run.sh start  <태그> <bit> <imp폴더> <앱> [제한초]
#   board_run.sh status <태그>
#   board_run.sh fetch  <태그>
#
# 먼저 되어 있어야 하는 것
#   - 앱을 플랫폼에 복사하고 200T 구현 폴더에서 release 로 빌드: tools/build_app.sh
#     (③ 은 bbht_grover_final 플랫폼(SRAM 128 KB)에도 들어가고, ② · ① 은 rvx/orca_sw.xml
#      플랫폼(SRAM 256 KB)이 필요합니다)
#   - 원격 접속: /fpga-flash 스킬의 check 가 통과하는 상태
# start 는 매번 비트스트림을 새로 굽고 앱을 올립니다. 측정을 다 마치면
# .claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie 를 따로 돌리십시오.
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
FLASH="$REPO/.claude/skills/fpga-flash/scripts/sdsl_fpga.sh"
WORKROOT="${ORCA_BOARD_WORK:-/tmp/orca_board}"   # 로그 · OCD 묶음 (저장소 밖)

cmd="${1:?start|status|fetch}"; tag="${2:?태그}"
WORK="$WORKROOT/$tag"

if [[ "$cmd" == start ]]; then
    BIT="${3:?bit}"; I="${4:?imp폴더}"; APP="${5:?앱}"; LIMIT="${6:-600}"
    P="$(cd "$I/.." && pwd)"; PLAT="$(basename "$P")"
    [[ -f "$I/$APP.sram.hex" && -f "$I/run_$APP.tcl" ]] || { echo "앱 hex/run tcl 이 없습니다: $I/$APP"; exit 1; }
    [[ ! -e "$WORK" ]] || { echo "태그가 이미 있습니다: $WORK"; exit 1; }
    if ssh sdsl-fpga 'pgrep -f "^\./[o]penocd_rvp |[u]art_capture.py" > /dev/null'; then
        echo "원격에서 다른 측정이 돌고 있습니다"; exit 1
    fi
    PKG="$WORK/pkg"; mkdir -p "$PKG/rvx_env" "$PKG/arch"
    cp "$I/ax7a200b.cfg" "$I/run_$APP.tcl" "$I/$APP.sram.hex" "$PKG/"
    cp /opt/rvx/local_setup/ocd/openocd_rvp "$PKG/"
    for f in ervp_jtag_memorymap_offset ervp_platform_controller_memorymap_offset \
             ervp_external_peri_group_memorymap_offset munoc_memorymap_offset \
             util jtag_function memory_function control_function mmio_function \
             misc_api platform_controller_api flash_api noc_api dump_api; do
        cp "/opt/rvx/rvx_devkit/env/ocd/$f.tcl" "$PKG/rvx_env/"
    done
    cp "$P"/arch/tcl/{memorymap_info,hw_info,ssw_info}.tcl "$PKG/arch/"
    cat > "$PKG/set_ocd_env.tcl" <<'EOF'
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
    cp "$REPO/hardware_bram/sim/uart_capture.py" "$PKG/"
    # 원격에서 떼어 돌릴 본체. 캡처를 먼저 띄우고 앱을 올린 뒤, 캡처가 끝날 때까지 OpenOCD 를 둡니다
    # (OpenOCD 를 내리면 어댑터가 플랫폼을 리셋합니다).
    cat > "$PKG/run.sh" <<EOF
#!/bin/bash
cd "\$(dirname "\$0")"
UART="\$(ls /dev/serial/by-id/*CP2102N* | head -1)"
chmod +x openocd_rvp
(sudo python3 uart_capture.py "\$UART" uart.log $LIMIT; echo \$? > capture.rc) > capture.out 2>&1 &
sleep 2
sudo ./openocd_rvp -f ax7a200b.cfg -c 'source run_$APP.tcl' > ocd.log 2>&1 &
while [ ! -f capture.rc ]; do sleep 5; done
sudo pkill -f '^\./openocd_rvp ' 2>/dev/null; sleep 1
echo "capture_rc=\$(cat capture.rc)" > done.txt
EOF
    chmod +x "$PKG/run.sh"
    sha256sum "$BIT" | sed "s|  .*|  $(basename "$BIT")|" > "$PKG/sha256.txt"
    (cd "$I" && sha256sum "$APP.sram.hex") >> "$PKG/sha256.txt"
    cp "$P/app/$APP/src/baseline_config.h" "$WORK/baseline_config.h" 2>/dev/null || true
    REMOTE="sdsl_fpga_runs/$(date +%Y-%m-%d_%H%M%S)_${PLAT}_$APP"
    echo "$REMOTE" > "$WORK/remote.txt"
    echo "$BIT" > "$WORK/bit.txt"
    ssh sdsl-fpga "mkdir -p ~/$REMOTE"
    scp -q -r "$PKG"/. "sdsl-fpga:$REMOTE/"
    echo "[굽기] $BIT"
    "$FLASH" program "$BIT" | tail -2
    ssh sdsl-fpga "cd ~/$REMOTE || exit 1; setsid nohup bash run.sh > run.out 2>&1 < /dev/null & disown" < /dev/null
    echo "[시작] sdsl-fpga:~/$REMOTE (제한 ${LIMIT}s)"
    exit 0
fi

REMOTE="$(cat "$WORK/remote.txt")"
if [[ "$cmd" == status ]]; then
    ssh sdsl-fpga "cd ~/$REMOTE && { cat done.txt 2>/dev/null || echo running; }; \
        echo lines=\$(grep -c '^SW_RUN,' uart.log 2>/dev/null); tail -2 uart.log 2>/dev/null"
elif [[ "$cmd" == fetch ]]; then
    scp -q "sdsl-fpga:$REMOTE/uart.log" "sdsl-fpga:$REMOTE/ocd.log" "sdsl-fpga:$REMOTE/sha256.txt" "$WORK/"
    scp -q "sdsl-fpga:$REMOTE/done.txt" "$WORK/" 2>/dev/null || true
    echo "$WORK"
fi
