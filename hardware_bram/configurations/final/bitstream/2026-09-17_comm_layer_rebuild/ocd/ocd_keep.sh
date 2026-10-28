#!/bin/bash
# 앱을 올린 뒤 OpenOCD 를 붙여 둔 채 유지합니다. 빠져나오면 JTAG 어댑터가
# 플랫폼을 리셋해 SRAM 에 올린 앱이 날아갑니다.
# openocd_rvp 는 /opt/rvx/local_setup/ocd/openocd_rvp 를 이 폴더로 복사해 쓰십시오.
cd "$(dirname "$0")"
exec ./openocd_rvp -f arty-100t.cfg -c "source run_bbht_console.tcl" > /tmp/ocd_daemon.log 2>&1
