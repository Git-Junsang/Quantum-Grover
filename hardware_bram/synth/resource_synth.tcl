# 5구성 공통조건 합성 -- run_resource.sh 가 경로를 환경변수로 넘겨 부릅니다.
#
# 대상 top 5벌(k4h4_e1 ... k3h3_e4_m2)과 ablation 공통소스, standalone top 이
# 쓰는 UART 브리지·데이터셋 생성기, 공통 XDC 가 전부 ../src_ablation/ 에
# 있습니다. 결과표는 results/2026-09-08_resource_ablation_5config/.
#
# 조건: Vivado 2024.2 / xc7a100tcsg324-1 / 공통 소스·공통 XDC / 합성까지만.
# 논문 주 수치는 여기서 나오는 u_main_ip 계층 사용량입니다.

set PART xc7a100tcsg324-1
set TOP bbht_standalone_top
set CFG $::env(CFG)
set TOP_FILE $::env(TOP_FILE)
set OUTDIR $::env(OUTDIR)
set CORE $::env(CORE)
set INCDIR $::env(INCDIR)
set SUPPORT $::env(SUPPORT)
set XDC $::env(XDC)
file mkdir $OUTDIR
set SRC [list $TOP_FILE $SUPPORT/bbht_uart_apb_bridge.v $SUPPORT/bbht_dataset_gen.v $CORE/bbht_grover_mmio.v $CORE/bbht_grover_main_ip.v $CORE/grover_arithmetic.v $CORE/grover_bbht.v $CORE/grover_checkpoint.v $CORE/grover_iteration.v $CORE/grover_loader.v $CORE/grover_measurement.v $CORE/grover_memories.v $CORE/grover_policy.v $CORE/grover_policy_impl_wrapper.v $CORE/grover_status.v]
foreach f $SRC { if {![file exists $f]} { error "SOURCE MISSING: $f" } }
read_verilog $SRC
read_xdc $XDC
synth_design -top $TOP -part $PART -include_dirs $INCDIR -flatten_hierarchy rebuilt
write_checkpoint -force $OUTDIR/post_synth.dcp
report_utilization -file $OUTDIR/post_synth_util.rpt
report_utilization -hierarchical -file $OUTDIR/post_synth_util_hier.rpt
report_timing_summary -file $OUTDIR/post_synth_timing.rpt
