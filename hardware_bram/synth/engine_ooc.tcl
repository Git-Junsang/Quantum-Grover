# iteration engines / square engines sweep 의 resource 보정용 OOC synthesis.
# sim/engine_sweep.py 가 generalize_main.prepare() 로 만든 source snapshot 과
# 그 구성의 adapter.v 를 넘깁니다. 여기서 재는 것은 bbht_rvx_wrapper 하나의
# synthesis 사용량이고, RVX SoC 나머지 · placement · routing · timing 은 아닙니다.
#
# 이 container 는 메모리 한도가 약 10 GB 입니다. general.maxThreads 만 1 로 두면
# synth.maxThreads 가 기본값 7 로 남아 synthesis 중 Killed 로 끝난 적이 있으므로
# 둘 다 1 로 묶습니다 (results/archive/implementation_pipeline/
# 2026-10-28_policy_rank_timing/evidence.md).
set src $::env(ENGINE_SRC)
set out $::env(ENGINE_OUT)
set part $::env(ENGINE_PART)
file mkdir $out
set_param general.maxThreads 1
set_param synth.maxThreads 1
set files [list]
foreach name {
    bbht_grover_main_ip.v grover_arithmetic.v grover_bbht.v grover_checkpoint.v
    grover_iteration.v grover_loader.v grover_measurement.v grover_memories.v
    grover_policy.v grover_status.v bbht_rvx_wrapper.v bbht_grover_mmio.v bbht_ahb_loader.v
    adapter.v
} { lappend files [file join $src $name] }
# adapter.v 끝의 simulation observer 는 `ifndef SYNTHESIS 로 감싸 있습니다.
# Vivado 가 이 macro 를 정의하지만 의존하지 않도록 명시합니다.
read_verilog $files
read_verilog -sv [list $src/grover_parallel.sv $src/grover_policy_parameterized.sv]
synth_design -top bbht_rvx_wrapper -part $part -mode out_of_context \
    -flatten_hierarchy rebuilt -include_dirs $src -verilog_define SYNTHESIS=1
create_clock -name accel_clk -period 10.0 [get_ports clk]
report_utilization -file [file join $out util.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out util_hier.rpt]
