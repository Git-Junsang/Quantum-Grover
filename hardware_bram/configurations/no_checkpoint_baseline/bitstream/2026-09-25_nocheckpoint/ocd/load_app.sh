#!/bin/bash
# WSL 에서 이 폴더로 들어와 실행합니다. Olimex JTAG 어댑터가 WSL 에 붙어 있어야 합니다.
cd "$(dirname "$0")"
chmod +x ./openocd_rvp
sudo ./openocd_rvp -f arty-100t.cfg -c "source run_bbht_console.tcl; exit"
