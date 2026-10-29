#!/usr/bin/env python3
"""One-configuration Main-IP integration smoke, policy replay and console checks.

The default checks a short Common500 prefix, not the full performance campaign.
All real iteration/measurement work runs in RTL through the actual C driver.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import dse
import generalize

ROOT=generalize.ROOT

MONITOR=r'''
    // Simulation observer: record actual solver transactions and Main-IP plan
    // acceptance. No testbench-derived cost is connected to hardware counters.
    integer monitor_fd,monitor_job=0,monitor_cycle=0,monitor_arg;
    string monitor_path;
    integer monitor_fault=0,monitor_reuse=0,monitor_reuse_phase=0;
    reg [7:0] monitor_saved_epoch=0;
    reg monitor_injected=0,monitor_force_active=0,monitor_flush_q=0,monitor_restart_q=0;
    localparam integer MONITOR_SLOTS=(CHECKPOINT_CAPACITY>4)?CHECKPOINT_CAPACITY:4;
    reg [MONITOR_SLOTS-1:0] monitor_saved_valid;
    reg [MONITOR_SLOTS*7-1:0] monitor_saved_slots;
    integer monitor_profile[0:31];
    integer monitor_phase;
    reg monitor_profile_active=0;
    initial begin
        if(!$value$plusargs("POLICY_TRACE=%s",monitor_path)) $fatal(1,"POLICY_TRACE is required");
        monitor_fd=$fopen(monitor_path,"w");
        if(!monitor_fd) $fatal(1,"cannot open policy observer file");
        if(!$value$plusargs("INJECT_MISMATCH=%d",monitor_fault)) monitor_fault=0;
        if(!$value$plusargs("INJECT_EPOCH_REUSE=%d",monitor_reuse)) monitor_reuse=0;
    end
    always @(posedge clk) begin
        monitor_cycle=monitor_cycle+1;
        if(rstnn && monitor_profile_active && u_main_ip.auto_policy_busy) begin
            monitor_phase=__POLICY_PHASE__;
            monitor_profile[monitor_phase]=monitor_profile[monitor_phase]+1;
        end
        monitor_flush_q<=rstnn && u_main_ip.planq_flush;
        monitor_restart_q<=rstnn && u_main_ip.enum_segment_plan_restart && !u_main_ip.cache_invalidate;
        if(rstnn && u_main_ip.enum_segment_plan_restart && !u_main_ip.cache_invalidate) begin
            monitor_saved_valid<=u_main_ip.ckpt_slot_valid;
            monitor_saved_slots<=u_main_ip.ckpt_slot_j_flat;
        end
    end
    // Sample settled signals on the falling edge. A start level at this edge
    // is accepted at the following rising edge, hence its timestamp is +1.
    // Done is already registered at the current rising edge.
    always @(negedge clk) begin
        if(monitor_force_active) begin
            release u_main_ip.planq_head_expected_j;
            monitor_force_active=0;
        end else if(rstnn && monitor_fault && !monitor_injected &&
            u_main_ip.planq_check_state && !u_main_ip.planq_empty &&
            u_main_ip.planq_head_expected_j!=7'd127) begin
            force u_main_ip.planq_head_expected_j=7'd127;
            monitor_injected=1;monitor_force_active=1;
            $fwrite(monitor_fd,"I %0d %0d\n",monitor_cycle,u_main_ip.auto_plan_epoch);
        end
        // Simulate epoch reuse while an old speculative transaction is in
        // flight: advance/flush once, then restore its old epoch value. The
        // completed old job must still be discarded by lifetime validity.
        if(rstnn && monitor_reuse) begin
            if(monitor_reuse_phase==0 && u_main_ip.auto_policy_busy && u_main_ip.policy_active_is_spec) begin
                monitor_saved_epoch=u_main_ip.policy_active_plan_epoch;
                force u_main_ip.plan_epoch_advance=1'b1;
                monitor_reuse_phase=1;
                $fwrite(monitor_fd,"R %0d %0d\n",monitor_cycle,monitor_saved_epoch);
            end else if(monitor_reuse_phase==1) begin
                release u_main_ip.plan_epoch_advance;
                force u_main_ip.auto_plan_epoch=monitor_saved_epoch;
                monitor_reuse_phase=2;
            end else if(monitor_reuse_phase==2 && !u_main_ip.auto_policy_busy) begin
                release u_main_ip.auto_plan_epoch;
                monitor_reuse_phase=3;
            end
        end
        if(rstnn) begin
            if(monitor_restart_q) begin
                if(u_main_ip.ckpt_slot_valid!==monitor_saved_valid || u_main_ip.ckpt_slot_j_flat!==monitor_saved_slots)
                    $fatal(1,"same-Oracle BBHT segment restart destroyed checkpoint metadata");
                $fwrite(monitor_fd,"T %0d %h\n",monitor_cycle,monitor_saved_valid);
            end
            if(u_main_ip.auto_policy_start) begin
                monitor_job=monitor_job+1;
                for(integer phase=0;phase<32;phase=phase+1) monitor_profile[phase]=0;
                monitor_profile_active=1;
                $fwrite(monitor_fd,"S %0d %0d %0d %0d %h %h %h\n",monitor_cycle+1,monitor_job,
                    u_main_ip.auto_policy_start_spec,u_main_ip.auto_plan_epoch,
                    u_main_ip.auto_policy_slot_valid_in,u_main_ip.auto_policy_slot_j_flat_in,
                    u_main_ip.auto_policy_window_flat_in);
            end
            if(u_main_ip.auto_policy_done) begin
                $fwrite(monitor_fd,"D %0d %0d %0d %0d %h %0d %0d\n",monitor_cycle,monitor_job,
                    u_main_ip.auto_policy_source_j,u_main_ip.auto_policy_next_count,
                    u_main_ip.auto_policy_next_j_flat,u_main_ip.auto_policy_error,u_main_ip.auto_policy_cycles_last);
                $fwrite(monitor_fd,"P %0d %0d",monitor_cycle,monitor_job);
                for(integer phase=0;phase<32;phase=phase+1) $fwrite(monitor_fd," %0d",monitor_profile[phase]);
                $fwrite(monitor_fd,"\n");
                monitor_profile_active=0;
            end
            if(u_main_ip.auto_accept_plan && !monitor_force_active)
                $fwrite(monitor_fd,"A %0d %0d %0d %0d %h %0d %0d %h %0d\n",monitor_cycle,
                    u_main_ip.auto_plan_epoch,u_main_ip.auto_current_j,u_main_ip.auto_input_s_count,
                    u_main_ip.auto_input_s_flat,u_main_ip.auto_incoming_source,u_main_ip.auto_incoming_count,
                    u_main_ip.auto_incoming_flat,u_main_ip.auto_accept_fifo);
            if(monitor_flush_q)
                $fwrite(monitor_fd,"F %0d %0d\n",monitor_cycle,u_main_ip.auto_plan_epoch);
        end
    end
'''

def save(path,data):path.write_text(json.dumps(data,indent=2)+'\n')
def run(command,log,*,cwd=None,env=None,stdout=None,timeout=None):
    with log.open('w') as stream:
        subprocess.run([str(item) for item in command],cwd=cwd,env=env,
            stdout=stdout if stdout is not None else stream,stderr=stream,check=True,timeout=timeout)

def prepare(data,out,limit,speculative,force_kernel,fault=False,epoch_reuse=False,per_m=None):
    if not force_kernel and (data['k'] not in (3,4) or data['h']>8 or data['e'] not in (1,2,4) or (data['e']!=4 and data['m']>1)):
        raise ValueError('legacy kernel requested for an unsupported production configuration')
    paths=[ROOT/'hardware_bram/src'/(name+('.sv' if name in dse.SV_CORE else '.v')) for name in dse.CORE+dse.COMM]
    paths += [ROOT/'hardware_bram/src/grover_param.vh',ROOT/'spec/generated/bbht_grover_csr.vh',
        ROOT/'spec/generated/bbht_grover_regs.h',ROOT/'hardware_bram/firmware/bbht_grover_driver.c',
        ROOT/'hardware_bram/firmware/bbht_grover_driver.h',ROOT/'hardware_bram/testbench/tb_bench500.cpp',
        ROOT/'hardware_bram/testbench/tb_console_seq.cpp']
    parameters={'CHECKPOINT_CAPACITY':data['k'],'LOOKAHEAD_SHOTS':data['h'],'NUMBER_OF_PES':data['e'],
        'POLICY_SEARCH_MODE':data['policy_mode'],'CHECKPOINT_MANUAL_ENABLE':0,
        'SPECULATIVE_PLANNING_ENABLE':int(speculative),'USE_TWO_LEVEL_SELECT':1}
    adapter=dse.TEMPLATE.read_text()
    for name,value in parameters.items():
        adapter,count=re.subn(rf'(parameter integer {name}\s*=\s*)\d+',rf'\g<1>{value}',adapter)
        if count!=1:raise ValueError(f'missing adapter parameter {name}')
    adapter,count=re.subn(r'(parameter integer BUILD_ROWS_PER_CYCLE\s*=\s*)`GP_BUILD_ROWS_PER_CYCLE_DEFAULT',rf'\g<1>{data["m"]}',adapter)
    if count!=1:raise ValueError('missing measurement parallelism adapter parameter')
    adapter=adapter.replace('.POLICY_SEARCH_MODE (POLICY_SEARCH_MODE),',
        '.POLICY_SEARCH_MODE (POLICY_SEARCH_MODE),\n'+
        f'        .GENERALIZED_RTL({int(force_kernel)}), .POLICY_FORCE_GENERIC({int(data["force_generic"])}),\n'+
        f'        .POLICY_SCAN_LANES({data["scan_lanes"]}), .POLICY_CANON_LANES({data["scan_lanes"]}),')
    hierarchy='u_main_ip.g_ckpt_plan_exec.g_auto_policy_k34'
    generic=data['force_generic'] or data['k'] not in (3,4) or data['h']>8
    if generic:
        phase=hierarchy+'.g_parameterized_policy.u_policy.g_general.u_policy.state'
    else:
        hierarchy+=('.g_parameterized_policy.u_policy.g_production.u_policy'
                    if force_kernel or data['force_generic'] else '.g_production_policy.u_auto_policy')
        phase=f'(({hierarchy}.fsm_state==4) ? (16+integer\'({hierarchy}.a_phase)) : integer\'({hierarchy}.fsm_state))'
    monitor=MONITOR.replace('__POLICY_PHASE__',phase)
    adapter=adapter[:adapter.rindex('endmodule')]+'\n`ifndef SYNTHESIS\n'+monitor+'\n`endif\nendmodule\n'
    selection=(f'first {per_m} seeds of each target count (BENCH_PER_M={per_m})' if per_m
               else f'{limit} ordered Common500 workloads')
    manifest={'config':data,'workloads':limit,'speculative':speculative,'force_generalized_kernel':force_kernel,
        'fault_injection':fault,'epoch_reuse_injection':epoch_reuse,
        'scope':f'Main-IP integration with {selection} and exact policy replay',
        'solver_backend':'generic' if generic else 'optimized',
        'sha256':{str(path.relative_to(ROOT)):dse.digest(path) for path in paths},
        'adapter_sha256':hashlib.sha256(adapter.encode()).hexdigest()}
    manifest_path=out/'manifest.json'
    if manifest_path.exists() and json.loads(manifest_path.read_text())!=manifest:
        raise ValueError('inputs changed; use a new output directory')
    out.mkdir(parents=True,exist_ok=True);save(manifest_path,manifest)
    source=out/'source';source.mkdir(exist_ok=True)
    for path in paths:
        shutil.copy2(path,source/path.name)
        if dse.digest(source/path.name)!=manifest['sha256'][str(path.relative_to(ROOT))]:
            raise ValueError('source changed while snapshotting: '+str(path))
    (source/'adapter.v').write_text(adapter)
    return manifest

def validate_trace(path,data):
    pending=None;completed=[];jobs=accepted=fifo=faults=flushes=reuses=generation=restarts=warm_restarts=0
    valid_plans=set();completed_cycles={};profile=[0]*32;profiled=0
    for line in path.read_text().splitlines():
        fields=line.split();kind=fields[0]
        if kind=='S':
            if pending is not None:raise ValueError('overlapping solver transactions')
            _,cycle,job,spec,epoch,valid,flat,window=fields
            mask=int(valid,16);flat=int(flat,16);window=int(window,16)
            held=tuple(sorted((flat>>(7*i))&127 for i in range(data['k']) if mask>>i&1))
            window=tuple((window>>(7*i))&127 for i in range(data['h']+1))
            expected=generalize.oracle(held,window,data['k'],data['policy_mode'])
            pending={'job':int(job),'cycle':int(cycle),'spec':int(spec),'epoch':int(epoch),
                     'held':held,'window':window,'expected':expected,'generation':generation};jobs+=1
        elif kind=='D':
            _,cycle,job,source,count,flat,error,cycles=fields
            if pending is None or pending['job']!=int(job):raise ValueError('solver completion without matching request')
            chosen=tuple((int(flat,16)>>(7*i))&127 for i in range(int(count)))
            if int(error) or (int(source),chosen)!=pending['expected'][:2]:
                raise ValueError(f'exact policy mismatch: {pending}, got {(source,chosen,error)}')
            if int(cycle)-pending['cycle']!=int(cycles):raise ValueError('policy counter differs from actual transaction clocks')
            valid_plans.add((pending['generation'],pending['epoch'],pending['held'],pending['window'][0],int(source),chosen))
            completed_cycles[int(job)]=int(cycles)
            completed.append(pending|{'source':int(source),'chosen':chosen});pending=None
        elif kind=='P':
            _,cycle,job,*counts=fields
            counts=[int(v) for v in counts]
            if len(counts)!=32 or sum(counts)!=completed_cycles[int(job)]:
                raise ValueError('passive phase counters differ from actual solver clocks')
            profile=[a+b for a,b in zip(profile,counts)];profiled+=1
        elif kind=='A':
            _,cycle,epoch,request,count,flat,source,next_count,next_flat,from_fifo=fields
            held=tuple((int(flat,16)>>(7*i))&127 for i in range(int(count)))
            chosen=tuple((int(next_flat,16)>>(7*i))&127 for i in range(int(next_count)))
            key=(generation,int(epoch),held,int(request),int(source),chosen)
            if key not in valid_plans:raise ValueError(f'plan accepted without matching exact current-context solve: {line}')
            accepted+=1;fifo+=int(from_fifo)
        elif kind=='I':faults+=1
        elif kind=='F':
            flushes+=1;generation+=1
        elif kind=='R':reuses+=1
        elif kind=='T':
            restarts+=1;warm_restarts+=int(int(fields[2],16)!=0)
        else:raise ValueError('unexpected observer row '+line)
    if not accepted:raise ValueError('no actual plans reached Executor')
    return {'solver_jobs':jobs,'completed_solver_jobs':len(completed),'accepted_plans':accepted,
        'fifo_accepted_plans':fifo,'injected_mismatches':faults,'flushes':flushes,
        'inflight_job_at_end':pending is not None,'epoch_reuse_injections':reuses,'same_oracle_restarts':restarts,
        'warm_same_oracle_restarts':warm_restarts,'profiled_jobs':profiled,'phase_cycles':profile,'errors':0}

def per_m_indices(per_m):
    # Common500 is ordered target count outer (1,4,16,64,256), 100 seeds inner.
    return [group*100+seed for group in range(5) for seed in range(per_m)]

def expected_iterations(data,limit,indices=None):
    workloads=dse.kh.load_workloads(dse.kh.DEFAULT_TRACE,dse.kh.DEFAULT_ROSTER,max(8,data['h']),
        None if indices is not None else limit)
    if indices is not None:workloads=[workloads[i] for i in indices]
    values=[]
    for workload in workloads:
        held=();physical=0
        for index,request in enumerate(workload.requested):
            window=tuple(workload.stream[index:index+data['h']+1])
            if len(window)!=data['h']+1:raise ValueError('reference request window truncated')
            source,held,_,_=generalize.oracle(held,window,data['k'],data['policy_mode']);physical+=request-source
        values.append(physical)
    return values

def execute(data,out,limit=2,speculative=True,force_kernel=True,fault=False,console=True,epoch_reuse=False,per_m=None):
    # per_m selects a stratified sample instead of the ordered prefix: the first
    # per_m seeds of every target count, so measurement-heavy workloads are kept.
    if per_m:limit=5*per_m
    indices=per_m_indices(per_m) if per_m else None
    selection_env={'BENCH_PER_M':str(per_m)} if per_m else {'BENCH_LIMIT':str(limit)}
    out=out.resolve();manifest=prepare(data,out,limit,speculative,force_kernel,fault,epoch_reuse,per_m)
    model_inputs={'sha256':manifest['sha256'],'adapter_sha256':manifest['adapter_sha256'],'build_flags':'assert,O2,real-driver-v1'}
    fingerprint=hashlib.sha256(json.dumps(model_inputs,sort_keys=True).encode()).hexdigest()[:20]
    build=Path('/tmp')/('bbht_general_model_'+fingerprint)
    build.mkdir(exist_ok=True);source=out/'source';obj=build/'obj'
    workload=out/'workload'
    if not workload.exists():
        run([sys.executable,ROOT/'software/reference_model_develop/tb_stimulus/dump_bench_workload.py',
            '--seeds','100','--out',workload],out/'workload_build.log')
    defines=['-DBBHT_HOST_TEST','-DBBHT_NO_PRINTF','-DBBHT_TIMEOUT=200000000']
    cached=(build/'model_inputs.json').exists() and (obj/'bench').exists()
    if cached and json.loads((build/'model_inputs.json').read_text())!=model_inputs:
        raise ValueError('compiled model input hash collision')
    rtl=[source/(name+('.sv' if name in dse.SV_CORE else '.v')) for name in dse.COMM+dse.CORE]
    if not cached:
        run(['gcc','-c','-O2',*defines,'-I',source,source/'bbht_grover_driver.c','-o',build/'driver.o'],out/'driver_build.log')
        run(['verilator','--cc','--exe','--build','-j',os.environ.get('BBHT_BUILD_JOBS','1'),'-Wno-fatal','-Wno-DECLFILENAME','--assert',
            '--Mdir',obj,'-CFLAGS',' '.join(defines+[f'-I{source}','-O2']),'-LDFLAGS',build/'driver.o',
            '-I'+str(source),*rtl,source/'adapter.v','--top-module','bbht_rvx_wrapper',
            source/'tb_bench500.cpp','-o','bench'],out/'build.log',cwd=build)
        save(build/'model_inputs.json',model_inputs)
    else:
        (out/'build.log').write_text('Reused source/adapter-hash-matched compiled model: '+str(build)+'\n')
    save(out/'model.json',{'directory':str(build),'inputs':model_inputs,'reused':cached})
    with (out/'bench.csv').open('w') as stdout:
        run([obj/'bench','+POLICY_TRACE='+str(out/'policy_trace.txt'),f'+INJECT_MISMATCH={int(fault)}',f'+INJECT_EPOCH_REUSE={int(epoch_reuse)}'],out/'simulation.log',
            env=os.environ|{'WL_DIR':str(workload)}|selection_env,stdout=stdout,timeout=int(os.environ.get('BBHT_SIM_TIMEOUT','1800')))
    # Check exact trajectory and physical work for this K/H, not a fixed H<=8
    # replay window. E/M affect execution schedule, never the policy definition.
    if fault:
        text=(out/'bench.csv').read_text()
        if '# DONE errors=0' not in text:raise ValueError('unfinished injected-fault run')
        rows=list(csv.DictReader(line for line in text.splitlines() if not line.startswith('#')))
        # The normal checker requires zero prediction mismatches. Temporarily
        # validate a distinct derived CSV with only the expected fault telemetry
        # neutralized, preserving the original measurement verbatim.
        with (out/'bench_logical_check.csv').open('w') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader()
            for row in rows:writer.writerow(row|{'mismatch':'0'})
            stream.write('# DONE errors=0\n')
        metrics=dse.validate_bench(out/'bench_logical_check.csv',limit,expected_iterations(data,limit,indices),indices)
    else:metrics=dse.validate_bench(out/'bench.csv',limit,expected_iterations(data,limit,indices),indices)
    trace=validate_trace(out/'policy_trace.txt',data)
    if fault and trace['injected_mismatches']!=1:raise ValueError('mismatch injection was not exercised')
    if fault and sum(int(row['mismatch']) for row in rows)!=1:
        raise ValueError('one injected mismatch must produce exactly one reported mismatch')
    if epoch_reuse and trace['epoch_reuse_injections']!=1:
        raise ValueError('epoch reuse was not exercised')
    if not speculative:
        if trace['fifo_accepted_plans'] or any(int(row['spec']) for row in csv.DictReader(line for line in (out/'bench.csv').read_text().splitlines() if not line.startswith('#'))):
            raise ValueError('speculation remained active in demand-only test')
    save(out/'integration.json',manifest|{'rtl_metrics':metrics,'policy_replay':trace,
        'status':'driver/Main-IP integration passed','fault_injection':fault,'epoch_reuse_injection':epoch_reuse})
    if console:
        binary=build/'console'
        run(['g++','-O2','-std=c++17',*defines,'-I'+str(obj),'-I'+str(source),
            '-I/usr/share/verilator/include','-I/usr/share/verilator/include/vltstd',source/'tb_console_seq.cpp',
            obj/'Vbbht_rvx_wrapper__ALL.a',obj/'verilated.o',obj/'verilated_threads.o',build/'driver.o',
            '-pthread','-latomic','-o',binary],out/'console_build.log')
        with (out/'console.csv').open('w') as stdout:
            run([binary,'+POLICY_TRACE='+str(out/'console_policy_trace.txt')],out/'console.log',
                env=os.environ|{'WL_DIR':str(workload)},stdout=stdout,timeout=300)
        with (out/'console.csv').open() as stream:rows=list(csv.DictReader(stream))
        enum=[row for row in rows if row['step']=='enum']
        if len(enum)!=1 or [int(v) for v in enum[0]['enum_idx'].split()]!=[8685,2852,507,4724]:raise ValueError('Enumeration result/order changed')
        console_trace=validate_trace(out/'console_policy_trace.txt',data)
        if console_trace['warm_same_oracle_restarts']<1:raise ValueError('warm same-Oracle segment restart was not exercised')
        save(out/'console.json',{'enum_indices':[8685,2852,507,4724],'policy_replay':console_trace,'errors':0})
    print(json.dumps({'config':data,'metrics':metrics,'trace':trace,'console':console,'errors':0}),flush=True)
    return json.loads((out/'integration.json').read_text())

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--workloads',type=int,default=2);parser.add_argument('--demand-only',action='store_true')
    parser.add_argument('--legacy-kernel',action='store_true');parser.add_argument('--inject-mismatch',action='store_true')
    parser.add_argument('--no-console',action='store_true');parser.add_argument('--inject-epoch-reuse',action='store_true')
    parser.add_argument('--per-m',type=int,help='stratified sample: first N seeds of each target count (overrides --workloads)')
    args=parser.parse_args()
    if not 1<=args.workloads<=500:parser.error('--workloads must be 1..500')
    if args.per_m is not None and not 1<=args.per_m<=100:parser.error('--per-m must be 1..100')
    if args.inject_mismatch and args.inject_epoch_reuse:parser.error('choose one scheduler injection per run')
    execute(generalize.config(args.config),args.out,args.workloads,not args.demand_only,
        not args.legacy_kernel,args.inject_mismatch,not args.no_console,args.inject_epoch_reuse,args.per_m)
