# 저장소 소스만으로 최종 Main IP 자원을 잽니다 (OOC 합성).
#
# 5구성 ablation 표는 standalone top 안의 u_main_ip 계층에서 뽑은 것이라
# 이 OOC 수치와 조건이 다릅니다. 정확히 같은 값이 나오길 기대하지 마십시오 --
# 최종 구성이 예상 규모(LUT 3.4만·DSP 128) 안에 있는지 보는 용도입니다.

set PART   xc7a100tcsg324-1
set SRC    $::env(SRC_DIR)
set OUTDIR $::env(OUTDIR)

file mkdir $OUTDIR

# 합성 경로에 들어가는 열. policy OOC 전용 두 파일은 최상위를 늘리므로 뺍니다.
set FILES [list \
    $SRC/bbht_grover_main_ip.v \
    $SRC/grover_arithmetic.v $SRC/grover_bbht.v $SRC/grover_checkpoint.v \
    $SRC/grover_iteration.v  $SRC/grover_loader.v $SRC/grover_measurement.v \
    $SRC/grover_memories.v   $SRC/grover_policy.v $SRC/grover_status.v]
foreach f $FILES { if {![file exists $f]} { error "소스 없음: $f" } }

read_verilog $FILES

# 보드 정본과 같은 파라미터입니다 (src/bbht_rvx_wrapper.v 가 넘기는 값).
synth_design -top bbht_grover_main_ip -part $PART -mode out_of_context \
             -include_dirs $SRC -flatten_hierarchy rebuilt \
             -generic CHECKPOINT_ENABLE=1 \
             -generic CKPT_K=3 \
             -generic POLICY_H_FUTURE=3 \
             -generic CKPT_MANUAL_ENABLE=0 \
             -generic AUTO_SPEC_ENABLE=1 \
             -generic INTRA_ENGINES=4

report_utilization             -file $OUTDIR/util.rpt
report_utilization -hierarchical -file $OUTDIR/util_hier.rpt
