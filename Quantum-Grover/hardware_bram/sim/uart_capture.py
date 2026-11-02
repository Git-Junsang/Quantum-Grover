#!/usr/bin/env python3
"""
보드 UART 를 읽어 파일로 남깁니다. 앱의 끝 표시 줄이나 시간 제한에서 멈춥니다.

    sudo python3 uart_capture.py <포트> <로그> [제한초]

board_run.sh 가 원격 보드 호스트에 복사해 앱을 올리기 **전에** 띄웁니다. 앱이 리셋 직후
찍는 머리말까지 받으려면 포트가 먼저 열려 있어야 합니다. 원격 계정이 dialout 그룹에
없어서 sudo 로 돌립니다.

끝 표시
  - bbht_paper_bench : "BBHT PAPER BOARD BENCHMARK PASS" / "... FAIL"
  - orca_sw_baseline 등 RVX 앱 공통 : "[RVX/END]" 로 시작하는 줄
bbht_console 은 끝나지 않는 셸이라 시간 제한으로만 멈춥니다.

종료 코드: 0 = 끝 표시를 봄, 2 = 시간 제한.
"""
import sys
import time

import serial

END = ("BBHT PAPER BOARD BENCHMARK PASS", "BBHT PAPER BOARD BENCHMARK FAIL", "[RVX/END]")


def main() -> int:
    port, log = sys.argv[1], sys.argv[2]
    limit = float(sys.argv[3]) if len(sys.argv) > 3 else 600.0
    s = serial.Serial(port, 115200, timeout=1)   # 8N1, 흐름 제어 없음 (기술문서 17장 17.3절)
    s.reset_input_buffer()
    t0 = time.time()
    with open(log, "w") as out:
        out.write(f"# capture start {time.strftime('%F %T')} port={port}\n")
        out.flush()
        buf = b""
        while time.time() - t0 < limit:
            buf += s.read(4096)
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                # 보드는 줄 끝을 "\n\r" 로 보내 다음 줄 머리에 "\r" 이 남습니다. 앞뒤 둘 다 떼야
                # 끝 표시를 startswith 로 알아봅니다(2026-10-08 첫 측정에서 놓친 원인).
                text = line.decode(errors="replace").strip("\r")
                out.write(text + "\n")
                out.flush()
                if text.startswith(END):
                    out.write(f"# capture end {time.strftime('%F %T')} ({time.time() - t0:.1f}s)\n")
                    return 0
        out.write(f"# capture timeout {limit}s\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
