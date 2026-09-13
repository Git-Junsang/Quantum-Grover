##=============================================================================
## bbht_standalone_arty100t.xdc   (rev.2)
##
## LPSoC BBHT/Grover K4/H4 -- RVX 없는 standalone 빌드용 제약
## Board  : Digilent Arty A7-100T (Rev. D/E)
## Device : xc7a100tcsg324-1
##
## rev.2 변경점: RVX 실측 빌드(imp_arty-100t_k4h4_2026-09-04)의
##   .Xil/BBHT_GROVER_FPGA_propImpl.xdc 와 대조하여 검증/수정.
##
##   - 클럭: MMCM/PLL 제거.  RVX 빌드에서 BBHT IP는 PLL 출력(50 MHz)이 아니라
##     E3 원시 클럭 sys_clk_pin(100 MHz)에 IBUF->BUFG 직결로 물려 있었음.
##     50 MHz 도메인은 rvc_orca 코어/주변장치 전용이었으므로 standalone에서는
##     통째로 사라짐.  따라서 clk_wiz IP가 필요 없음.
##   - 핀: E3 / C2 / D10 / A9 / H5,J5,T9,T10 은 propImpl.xdc와 일치 확인 완료.
##   - 버튼 D9/C9 는 Digilent 마스터 기준.  RVX는 버튼 대신 슬라이드 스위치
##     (A8/C11/C10)를 썼으므로 이 두 핀은 RVX 빌드로 검증된 바 없음.
##
## RVX 신호명 대조:
##   external_clk_0  -> CLK100MHZ
##   external_rstnn  -> ck_rst
##   printf_tx       -> uart_rxd_out   (FPGA -> PC)
##   printf_rx       -> uart_txd_in    (PC -> FPGA)
##   led_list[3:0]   -> led[3:0]
##=============================================================================

##-----------------------------------------------------------------------------
## Clock -- 외부 100 MHz, BUFG 직결
##
## RVX의 clk_and_rst.xdc와 동일한 제약.  create_clock 이름을 sys_clk_pin으로
## 유지하면 RVX 빌드의 타이밍 리포트와 클럭 이름이 그대로 대응되어
## WNS 비교가 직접 가능함 (RVX 빌드 기준값: sys_clk_pin WNS = +0.236 ns).
##-----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }]
set_input_jitter [get_clocks sys_clk_pin] 0.100

## 주의: RVX 빌드의 100 MHz WNS 여유는 +0.236 ns 뿐이었고, 최악 경로는
##   u_main_ip/u_measure_verify/u_born/lane_index_reg  (19 logic levels, CARRY4 x14)
## 로 IP 내부에 있음.  데이터 경로 지연 9.255 ns 중 route가 4.672 ns(50.5%)이므로
## SoC 제거로 혼잡도가 줄면 개선 여지가 있으나, logic 4.583 ns는 고정임.
## standalone 합성 후 이 경로의 WNS를 반드시 재확인할 것.

##-----------------------------------------------------------------------------
## Reset -- 보드 전용 리셋 버튼 (active-low, 눌리면 0)
##-----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports { ck_rst }]

## 비동기 입력이므로 top 안에서 2단 동기화 후 사용할 것.
set_false_path -from [get_ports { ck_rst }]

##-----------------------------------------------------------------------------
## USB-UART (FTDI FT2232H 브리지)
##   uart_txd_in  : PC가 보내는 선  -> FPGA 입력  (RVX: printf_rx, A9)
##   uart_rxd_out : FPGA가 보내는 선 -> PC 입력   (RVX: printf_tx, D10)
##   이름이 PC 기준이라 헷갈리기 쉬우니 주의.
##-----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { uart_txd_in  }]
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }]

set_false_path -from [get_ports { uart_txd_in }]
set_false_path -to   [get_ports { uart_rxd_out }]

##-----------------------------------------------------------------------------
## 버튼 -- btn[0] = 수동 start, btn[1] = 예비
## 주의: RVX 빌드에는 이 핀이 쓰이지 않았음.  Digilent 마스터 XDC 기준.
##-----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]

set_false_path -from [get_ports { btn[*] }]

##-----------------------------------------------------------------------------
## LED -- 상태 표시 (RVX led_list[3:0]과 동일 핀)
##   led[0] busy, led[1] done, led[2] result_valid, led[3] error
##-----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

set_false_path -to [get_ports { led[*] }]

##-----------------------------------------------------------------------------
## 컨피그레이션 -- SPI 플래시 부팅용
##
## JTAG로만 올릴 거면 아래 CONFIG_MODE/SPI_BUSWIDTH는 없어도 됨.
## 주의: RVX set_fpga.tcl은 FLASH_INTERFACE_TYPE=spix4 인데 RVX pinmap의
## spi_flash.xdc에는 sdq0/sdq1 두 선만 배선돼 있음.  x4로 쓰려면 dq2/dq3
## 배선을 먼저 확인해야 하므로, 우선 x1로 시작하는 것이 안전함.
##-----------------------------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO     [current_design]

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1        [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33         [current_design]
set_property CONFIG_MODE SPIx1                      [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE        [current_design]

##-----------------------------------------------------------------------------
## 미사용 핀 처리
##-----------------------------------------------------------------------------
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]
