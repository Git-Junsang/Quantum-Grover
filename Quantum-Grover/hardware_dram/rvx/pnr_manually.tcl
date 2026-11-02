#=====================================================================
# pnr_manually.tcl -- bbht_grover_dram 의 배치/배선 순서 (arty-100t)
#
# RVX 의 구현 스크립트(rvx_devkit/env/xilinx/__implement.tcl)는
#   ${PLATFORM_DIR}/user/fpga/${FPGA_NAME}/pnr_manually.tcl
# 이 있으면 기본 "opt_design; place_design; route_design" 대신 이 파일을
# source 합니다. install_to_platform.sh 가 여기로 복사합니다. 합성, CDC
# false path, 체크포인트·리포트·비트스트림 쓰기는 RVX 흐름 그대로입니다.
#
# 왜 필요한가 (2026-09-25 첫 구현, 기본 흐름)
#   include_slow_dram 을 켜면 RVX 가 NoC 클럭(clk_noc)을 MIG 의 ui_clk 로
#   바꿉니다. arty-100t 의 MIG 설정(mig_b.prj, 2:1)에서 ui_clk 는 150 MHz
#   (clk_pll_i, 6.667 ns) 이고, 시스템 SRAM 의 NoC 인터페이스
#   (i_snim_i_system_sram) 안 13단 경로가 -0.659 ns 로 79곳 모자랐습니다.
#   지연의 70% 가 배선이라 RTL 이 아니라 배치/배선으로 푸는 쪽입니다.
#   (이 경로는 RVX 가 만든 NoC 로직이라 우리가 RTL 을 고칠 수 없습니다.)
#   같은 빌드의 clk_accel(100 MHz) 쪽 -2.1 ns 는 AXI 브리지 RTL 을 고쳐
#   풀었습니다(grover_dram_axi_bridge.v 의 awlen 큐 lenq).
#   최종 빌드(2026-09-25 3차)는 배선 뒤 WNS +0.005 ns 로, 여유가 얇습니다.
#
# 순서
#   1. opt_design Explore
#   2. place_design ExtraTimingOpt -- 타이밍 우선 배치
#   3. phys_opt_design AggressiveExplore -- 배치 뒤 복제·재배치
#   4. route_design Explore
#   5. 배선 뒤에도 음수 슬랙이면 phys_opt_design 한 번 더
#=====================================================================

# 셋업 WNS 를 찍어 두는 도우미. 로그에서 단계별로 얼마나 줄었는지 봅니다.
proc bbht_report_wns {stage} {
    set p [get_timing_paths -max_paths 1 -nworst 1 -setup]
    if {[llength $p] == 0} {
        puts "\[BBHT_PNR\] $stage WNS=n/a"
        return 0.0
    }
    set wns [get_property SLACK $p]
    puts "\[BBHT_PNR\] $stage WNS=$wns"
    return $wns
}

puts "\[BBHT_PNR\] bbht_grover_dram pnr_manually.tcl"

opt_design -directive Explore
bbht_report_wns "opt"

place_design -directive ExtraTimingOpt
bbht_report_wns "place"

phys_opt_design -directive AggressiveExplore
bbht_report_wns "phys_opt(place)"

route_design -directive Explore
set wns [bbht_report_wns "route"]

if {$wns < 0.0} {
    phys_opt_design -directive AggressiveExplore
    bbht_report_wns "phys_opt(route)"
}
