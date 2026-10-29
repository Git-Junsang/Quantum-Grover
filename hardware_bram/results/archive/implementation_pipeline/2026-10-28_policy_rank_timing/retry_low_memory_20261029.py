#!/usr/bin/env python3
"""Resume the frozen build with serial synthesis after three killed attempts.

The original RTL, app, clock and timing constraints remain frozen. This worker
reuses their completed RTL/SoC checks and adds only a recorded synthesis hook.
It runs detached, owns the existing Vivado lock, and stops if the result gate
fails. Board verification is the same already-authorized stage as the original
worker and can run only after the bitstream and both timing checks pass.
"""
from pathlib import Path
import fcntl
import json
import os
import shutil
import subprocess
import time
import traceback
import pipeline_worker as p

RECOVERY=p.OUT/'recovery_low_memory_20261029'
ATTEMPT=p.OUT/'implementation_attempt_4_low_memory'
SYNTH_HOOK=p.PLATFORM/'user/fpga/ax7a200b/syn_manually.tcl'
HOOK_TEXT=('set_param general.maxThreads 1\n'
           'set_param synth.maxThreads 1\n'
           'puts "BBHT serial synthesis: general=[get_param general.maxThreads] synth=[get_param synth.maxThreads]"\n'
           'synth_design\n')

def state(value,**extra):
    p.state(value,**extra)
    shutil.copy2(p.OUT/'pipeline_state.json',RECOVERY/'pipeline_state.json')

def main():
    RECOVERY.mkdir(exist_ok=False)
    ATTEMPT.mkdir(exist_ok=False)
    shutil.copy2(p.OUT/'pipeline_state.json',RECOVERY/'previous_pipeline_state.json')
    p.installed_sources_match()
    expected=json.loads((p.OUT/'pipeline_inputs.json').read_text())
    for relative,sha in expected['protected_firmware_sha256'].items():
        assert p.digest(p.ROOT/relative)==sha,'Protected firmware changed: '+relative
    assert json.loads((p.OUT/'soc_equivalence.json').read_text())['errors']==0
    assert json.loads((p.CELL/'sim.json').read_text())['validated_workloads']==500
    assert not SYNTH_HOOK.exists(),'Existing synthesis hook must be preserved'
    state('waiting_for_vivado_slot',attempt=4,recovery='serial synthesis')
    with open('/tmp/bbht_vivado_pipeline.lock','w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        while subprocess.run(['pgrep','-f','[v]ivado'],stdout=subprocess.DEVNULL).returncode==0:
            time.sleep(30)
        p.installed_sources_match()
        SYNTH_HOOK.write_text(HOOK_TEXT)
        shutil.copy2(SYNTH_HOOK,ATTEMPT/'syn_manually.tcl')
        hook=p.PLATFORM/'user/fpga/ax7a200b/pnr_manually.tcl'
        hook.write_text('opt_design -directive Explore\n'
                        'place_design -directive Explore\n'
                        'phys_opt_design -directive AggressiveExplore\n'
                        'route_design -directive Explore\n'
                        'phys_opt_design -directive Explore\n'
                        'route_design -directive Explore\n')
        shutil.copy2(hook,ATTEMPT/'pnr_manually.tcl')
        (RECOVERY/'inputs.json').write_text(json.dumps({
            'platform':p.PLATFORM_NAME,'source_manifest':'../pipeline_inputs.json',
            'platform_input_hashes_verified':len(expected['platform_input_sha256']),
            'general_threads':1,'synthesis_threads':1,
            'synthesis_hook_sha256':p.digest(SYNTH_HOOK),
            'pnr_hook_sha256':p.digest(hook),
            'rtl_and_clock_constraints_changed':False,
            'reason':'Three previous Vivado processes were Killed during synthesis; service memory limit is 10 GiB.',
            'reused_checks':['same-source 500-workload RTL','90-check full SoC console'],
        },indent=2)+'\n')
        state('implementation',attempt=4,strategy='explore_serial_synthesis',max_attempts=4)
        p.run([p.SYN,'start',p.PLATFORM_NAME,'--threads=1','--app=bbht_console'],ATTEMPT/'start.log')
        implementation=Path((p.PLATFORM/'.fpga_syn_rvx_last').read_text().strip())
        while not (implementation/'fpga_syn_rvx.done').exists():
            time.sleep(30)
        rc=int((implementation/'fpga_syn_rvx.done').read_text().strip())
        gate=p.run([p.SYN,'result',p.PLATFORM_NAME],ATTEMPT/'result.log',allowed=tuple(range(256)))
        for name in ('route_timing_summary.rpt','route_timing_max.rpt','route_util.rpt'):
            report=implementation/'imp_result'/name
            if report.exists():shutil.copy2(report,ATTEMPT/name)
        shutil.copy2(implementation/'fpga_syn_rvx.log',ATTEMPT/'vivado.log')
        (ATTEMPT/'status.json').write_text(json.dumps({'implementation_exit':rc,'gate_exit':gate,
            'strategy':'explore_serial_synthesis','source_manifest':'../pipeline_inputs.json'},indent=2)+'\n')
        if rc or gate:
            raise RuntimeError('Serial synthesis/implementation did not pass the bitstream and timing gate; see attempt 4 logs.')
        p.rvx(['make','bbht_paper_bench'],'paper_bench_build.log',implementation)
    state('board_preflight')
    for relative,sha in expected['board_tool_sha256'].items():
        assert p.digest(p.ROOT/relative)==sha,'Board tool changed after launch: '+relative
    p.run([p.FLASH,'check'],'board_preflight.log')
    p.run(['ssh','-o','BatchMode=yes','sdsl-fpga',
        "if pgrep -f '[o]penocd_rvp|[o]penocd .*ax7a200b' >/dev/null; then echo 'Existing OpenOCD session'; exit 3; fi"],
        'board_exclusive_check.log')
    state('board_common500')
    p.run(['bash',p.ROOT/'hardware_bram/sim/board_run.sh','K3H3_E4_M2','bbht_paper_bench','600'],
        'board_run.log',env=os.environ|{'BOARD_PLATFORM':p.PLATFORM_NAME,
        'BOARD_BENCH':str(p.CELL/'bench.csv'),'BOARD_WORK':str(p.OUT/'board'),'BOARD_AUTO_RESTORE':'1'})
    state('board_verified',commit='not performed',
        note='Strict 1000-row RTL/board cycle and result comparison passed; flash design restored.')

if __name__=='__main__':
    try:
        main()
    except BaseException as error:
        RECOVERY.mkdir(exist_ok=True)
        state('failed',failed_stage=p.stage,error=str(error))
        traceback.print_exc()
        raise SystemExit(1)
