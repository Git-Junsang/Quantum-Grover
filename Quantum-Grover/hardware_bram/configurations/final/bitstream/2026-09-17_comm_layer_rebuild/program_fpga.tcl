# Vivado 배치 모드로 비트스트림을 굽습니다.
#   vivado -mode batch -source program_fpga.tcl
# 이 파일과 같은 폴더의 .bit 를 씁니다.
set here [file dirname [file normalize [info script]]]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE [file join $here bbht_grover_upgrade_fpga.arty-100t.bit] $dev
set_property PROBES.FILE {} $dev
program_hw_devices $dev
puts "PROGRAM DONE: [get_property PROGRAM.FILE $dev]"
close_hw_target
disconnect_hw_server
close_hw_manager
