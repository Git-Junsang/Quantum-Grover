#!/usr/bin/env python3
"""Detached, single-configuration RTL -> 200T -> board verification job.

Inputs are frozen before launch. Progress is recorded locally; this process
does not require an assistant to poll synthesis or place-and-route progress.
Board programming occurs only after RTL/SoC checks and nonnegative WNS/WHS.
"""
from pathlib import Path
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import traceback

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[2]
PLATFORM_NAME='bbht_grover_k3h3_e4_m2_rankfix_20261028'
PLATFORM=Path('/opt/rvx/platform')/PLATFORM_NAME
CELL=OUT/'k3h3_e4_b2_p6'
SYN=ROOT/'.claude/skills/fpga-syn-rvx/scripts/fpga_syn_rvx.sh'
FLASH=ROOT/'.claude/skills/fpga-flash/scripts/sdsl_fpga.sh'
sys.path.insert(0,str(ROOT/'hardware_bram/sim'))
import dse

stage='submitted'
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def state(value,**extra):
    global stage
    stage=value
    data={'stage':value,'updated_utc':datetime.now(timezone.utc).isoformat(),
          'pid':os.getpid(),'platform':PLATFORM_NAME,**extra}
    temp=OUT/'pipeline_state.tmp'
    temp.write_text(json.dumps(data,indent=2)+'\n')
    temp.replace(OUT/'pipeline_state.json')
    print(json.dumps(data),flush=True)

def run(command,log,cwd=ROOT,env=None,allowed=(0,)):
    command=[str(item) for item in command]
    with (OUT/log).open('w') as stream:
        result=subprocess.run(command,cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT)
    if result.returncode not in allowed:
        raise RuntimeError(f'{log}: command exited {result.returncode}')
    return result.returncode

def rvx(command,log,cwd):
    return run(['bash','-c','source /opt/rvx/rvx_setup.sh && exec "$@"','rvx-task',*command],log,cwd)

def installed_sources_match():
    expected=json.loads((OUT/'pipeline_inputs.json').read_text())
    for relative,sha in expected['platform_input_sha256'].items():
        assert digest(PLATFORM/relative)==sha, 'Frozen platform input changed: '+relative

def console_reference():
    fingerprint=hashlib.sha256((str(OUT)+'k3h3_e4_b2_p6').encode()).hexdigest()[:16]
    build=Path('/tmp/bbht_dse_'+fingerprint)
    obj=build/'obj'
    binary=build/'console_reference'
    run(['g++','-O2','-std=c++17','-DBBHT_HOST_TEST','-DBBHT_NO_PRINTF',
         '-DBBHT_TIMEOUT=200000000','-I'+str(obj),'-I'+str(build/'src'),
         '-I/usr/share/verilator/include','-I/usr/share/verilator/include/vltstd',
         OUT/'source/tb_console_seq.cpp',obj/'Vbbht_rvx_wrapper__ALL.a',
         obj/'verilated.o',obj/'verilated_threads.o',build/'driver.o',
         '-pthread','-latomic','-o',binary],'console_build.log')
    with (OUT/'console_reference.csv').open('w') as stdout,(OUT/'console_reference.log').open('w') as stderr:
        subprocess.run([str(binary)],env=os.environ|{'WL_DIR':str(OUT/'workload')},
                       stdout=stdout,stderr=stderr,check=True)

def main():
    installed_sources_match()
    state('solver_regression')
    run([sys.executable,OUT/'run_units.py'],'unit_runner.log')
    config=json.loads((OUT/'config.json').read_text())
    cells=dse.config_cells(config)
    assert len(cells)==1
    state('rtl_common500')
    # prepare() already captured the source. Do not compare against the live
    # workspace here: other authorized RTL work may proceed after launch.
    dse.policy(OUT,cells[0],500)
    dse.simulate(OUT,cells[0],config)
    dse.report(OUT,config,cells)
    console_reference()

    state('soc_console')
    rvx(['make','syn'],'soc_generate.log',PLATFORM)
    rvx(['make','sim_rtl'],'soc_compile.log',PLATFORM)
    rvx(['make','bbht_console.sim'],'soc_run.log',PLATFORM/'sim_rtl')
    shutil.copy2(PLATFORM/'sim_rtl/qtsim.log',OUT/'soc_qtsim.log')
    run([sys.executable,ROOT/'hardware_bram/sim/soc_console_check.py',OUT/'soc_qtsim.log',
         '--ref',OUT/'console_reference.csv','--transcript',OUT/'soc_transcript.txt',
         '--out',OUT/'soc_crosscheck.txt'],'soc_historical_check.log',
         env=os.environ|{'PYTHONPATH':str(ROOT/'software/host_fpga_develop')},allowed=tuple(range(256)))
    run([sys.executable,OUT/'verify_soc.py'],'soc_verify.log')

    state('waiting_for_vivado_slot')
    with open('/tmp/bbht_vivado_pipeline.lock','w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        while subprocess.run(['pgrep','-f','[v]ivado'],stdout=subprocess.DEVNULL).returncode==0:
            time.sleep(30)
        installed_sources_match()
        strategies=[
            ('explore','Explore','Explore','AggressiveExplore','Explore'),
            ('timing','ExtraTimingOpt','AggressiveExplore','AggressiveExplore','ExploreWithRemap'),
            ('congestion','AltSpreadLogic_high','Explore','Explore','Explore')]
        passed=False
        for number,(label,placement,routing,physical,optimization) in enumerate(strategies,1):
            installed_sources_match()
            attempt=OUT/('implementation_attempt_'+str(number))
            attempt.mkdir(exist_ok=True)
            hook=PLATFORM/'user/fpga/ax7a200b/pnr_manually.tcl'
            hook.write_text(f'opt_design -directive {optimization}\n'
                            f'place_design -directive {placement}\n'
                            f'phys_opt_design -directive {physical}\n'
                            f'route_design -directive {routing}\n'
                            'phys_opt_design -directive Explore\n'
                            'route_design -directive Explore\n')
            shutil.copy2(hook,attempt/'pnr_manually.tcl')
            state('implementation',attempt=number,strategy=label,max_attempts=len(strategies))
            run([SYN,'start',PLATFORM_NAME,'--threads=2','--app=bbht_console'],attempt/'start.log')
            implementation=Path((PLATFORM/'.fpga_syn_rvx_last').read_text().strip())
            while not (implementation/'fpga_syn_rvx.done').exists(): time.sleep(30)
            rc=int((implementation/'fpga_syn_rvx.done').read_text().strip())
            result_rc=run([SYN,'result',PLATFORM_NAME],attempt/'result.log',allowed=tuple(range(256)))
            for report_name in ('route_timing_summary.rpt','route_timing_max.rpt','route_util.rpt'):
                report=implementation/'imp_result'/report_name
                if report.exists(): shutil.copy2(report,attempt/report_name)
            shutil.copy2(implementation/'fpga_syn_rvx.log',attempt/'vivado.log')
            (attempt/'status.json').write_text(json.dumps({'implementation_exit':rc,'gate_exit':result_rc,
                'strategy':label,'input_sha256':json.loads((OUT/'pipeline_inputs.json').read_text())['platform_input_sha256']},indent=2)+'\n')
            if rc==0 and result_rc==0:
                passed=True
                break
        if not passed:
            raise RuntimeError('All three physical implementation strategies failed; see archived attempt reports. RTL changes require a new source snapshot.')
        rvx(['make','bbht_paper_bench'],'paper_bench_build.log',implementation)

    state('board_preflight')
    expected=json.loads((OUT/'pipeline_inputs.json').read_text())
    for relative,sha in expected['board_tool_sha256'].items():
        assert digest(ROOT/relative)==sha,'Board tool changed after launch: '+relative
    run([FLASH,'check'],'board_preflight.log')
    # A concurrent app-loading session must be left untouched.
    run(['ssh','-o','BatchMode=yes','sdsl-fpga',
         "if pgrep -f '[o]penocd_rvp|[o]penocd .*ax7a200b' >/dev/null; then echo 'Existing OpenOCD session'; exit 3; fi"],
        'board_exclusive_check.log')
    state('board_common500')
    run(['bash',ROOT/'hardware_bram/sim/board_run.sh','K3H3_E4_M2','bbht_paper_bench','600'],
        'board_run.log',env=os.environ|{'BOARD_PLATFORM':PLATFORM_NAME,
        'BOARD_BENCH':str(CELL/'bench.csv'),'BOARD_WORK':str(OUT/'board'),
        'BOARD_AUTO_RESTORE':'1'})
    state('board_verified',commit='pending review of recorded results',
          note='Strict 1000-row RTL/board cycle and result comparison passed; flash design restored.')

if __name__=='__main__':
    try: main()
    except BaseException as error:
        failed_stage=stage
        state('failed',failed_stage=failed_stage,error=str(error))
        traceback.print_exc()
        raise SystemExit(1)
