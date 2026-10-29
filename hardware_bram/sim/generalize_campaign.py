#!/usr/bin/env python3
"""Explicit, resumable Common500 campaign using one fixed E/M configuration.

Each cell runs the real driver and the actual Main-IP RTL. The selected K/H
range is opt-in; this runner never invokes synthesis, SoC or board programming.
Results retain source hashes, actual counters, exact policy replay and passive
solver phase counts. Complete cells may be reused only with matching inputs.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import threading
import time

import generalize
import generalize_main as main
import dse

PHASES={0:'idle',1:'memo_clear',2:'universe_build',3:'map',4:'prepare',5:'scan',
        6:'memo_probe',7:'memo_response',8:'evaluate',9:'replay',10:'finish',
        11:'return',12:'cache_read',13:'unique_root'}

def save(path,value):
    temporary=path.with_suffix(path.suffix+'.tmp')
    temporary.write_text(json.dumps(value,indent=2)+'\n')
    temporary.replace(path)

def report(out,rows):
    fields=['k','h','e','m','workloads','cycles','iter','policy_cycles','policy_stall',
            'policy_actions','solver_jobs','max_solver_cycles','elapsed_seconds','reused','evidence']
    with (out/'summary.csv').open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=fields);writer.writeheader()
        writer.writerows({k:row[k] for k in fields} for row in sorted(rows,key=lambda r:(r['k'],r['h'])))

def plot(out,rows,plan):
    os.environ.setdefault('MPLCONFIGDIR','/tmp/bbht-general-campaign-matplotlib')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    ks=plan['capacities'];hs=plan['lookahead_shots']
    fig,axes=plt.subplots(1,3,figsize=(18,5.8),constrained_layout=True)
    for ax,field,title,scale in zip(axes,['policy_cycles','policy_stall','cycles'],
            ['Policy cycles','Exposed policy stall','Total accelerator cycles'],[1000,1000,1000000]):
        values=np.full((len(ks),len(hs)),np.nan)
        for row in rows:values[ks.index(row['k']),hs.index(row['h'])]=row[field]/scale
        image=ax.imshow(np.ma.masked_invalid(values),origin='lower',aspect='auto',cmap='YlOrRd')
        ax.set_xticks(range(len(hs)),hs);ax.set_yticks(range(len(ks)),ks)
        ax.set_xlabel('Lookahead-Shots');ax.set_ylabel('Checkpoint-Capacity')
        ax.set_title(title+(' (thousands)' if scale==1000 else ' (millions)'))
        for i,k in enumerate(ks):
            for j,h in enumerate(hs):
                if np.isfinite(values[i,j]):ax.text(j,i,f'{values[i,j]:.1f}',ha='center',va='center',fontsize=8)
        fig.colorbar(image,ax=ax,shrink=.75)
    fig.suptitle(f"Actual RTL, {plan['workloads']} workloads per cell; iteration engines={plan['iteration_engines']}, square engines={plan['square_engines']}")
    fig.savefig(out/'kh_heatmap.png',dpi=180)
    fig.savefig(out/'kh_heatmap.svg')
    plt.close(fig)

def run(config,plan,out,reuse):
    out=out.resolve();out.mkdir(parents=True,exist_ok=True)
    reuse=[path.resolve() for path in reuse]
    ks=plan['capacities'];hs=plan['lookahead_shots'];limit=plan['workloads']
    if not ks or not hs or any(type(v)is not int or not 1<=v<=10 for v in ks+hs):
        raise ValueError('capacity/lookahead entries must be integers in 1..10')
    if len(set(ks))!=len(ks) or len(set(hs))!=len(hs):raise ValueError('duplicate cell parameters')
    if plan['workers'] not in (1,2):raise ValueError('use one or two workers')
    if not 1<=limit<=500:raise ValueError('workloads must be 1..500')
    base=config|{'e':plan['iteration_engines'],'m':plan['square_engines'],
                 'policy_mode':plan['policy_mode'],'force_generic':plan['force_generic']}
    core=[generalize.ROOT/'hardware_bram/src'/(name+('.sv' if name in dse.SV_CORE else '.v')) for name in dse.CORE+dse.COMM]
    extras=[generalize.ROOT/relative for relative in ('hardware_bram/src/grover_param.vh',
        'spec/generated/bbht_grover_csr.vh','spec/generated/bbht_grover_regs.h',
        'hardware_bram/firmware/bbht_grover_driver.c','hardware_bram/firmware/bbht_grover_driver.h',
        'hardware_bram/testbench/tb_bench500.cpp','hardware_bram/testbench/tb_console_seq.cpp')]
    hashes={str(path.relative_to(generalize.ROOT)):dse.digest(path) for path in core+extras}
    helpers=[Path(generalize.__file__),Path(main.__file__),Path(__file__),dse.TEMPLATE]
    manifest={'base_config':base,'plan':plan,'sha256':hashes,
              'tools_sha256':{str(path.relative_to(generalize.ROOT)):dse.digest(path) for path in helpers},
              'scope':'actual parameterized Main-IP RTL Common500; no full-SoC or physical implementation'}
    if (out/'manifest.json').exists() and json.loads((out/'manifest.json').read_text())!=manifest:
        raise ValueError('campaign inputs changed; use a new output directory')
    save(out/'manifest.json',manifest)
    snapshot=out/'source';snapshot.mkdir(exist_ok=True)
    for path in core+extras+helpers:
        destination=snapshot/path.relative_to(generalize.ROOT);destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(path,destination)
    lock=threading.Lock();started=time.monotonic();rows=[];errors=[];active=[]
    total=len(ks)*len(hs)
    def progress():
        save(out/'progress.json',{'cells':total,'completed':len(rows),'failed':errors,'active':active,
            'elapsed_seconds':round(time.monotonic()-started,1),'workers':plan['workers']})
        report(out,rows)
    def cell(k,h):
        data=base|{'k':k,'h':h};name=f'k{k}h{h}e{base["e"]}m{base["m"]}'
        begin=time.monotonic();directory=out/name;record=None;reused=False
        for path in core+extras+helpers:
            expected=hashes.get(str(path.relative_to(generalize.ROOT)),manifest['tools_sha256'].get(str(path.relative_to(generalize.ROOT))))
            if dse.digest(path)!=expected:raise ValueError('live source changed during campaign: '+str(path))
        with lock:active.append(name);progress()
        print(json.dumps({'state':'running','cell':name}),flush=True)
        for candidate in [directory,*reuse]:
            if (candidate/'integration.json').exists():
                r=json.loads((candidate/'integration.json').read_text())
                if r['config']==data and r['workloads']==limit and r['sha256']==hashes and r.get('speculative') and r.get('force_generalized_kernel'):
                    if r['rtl_metrics']['validated_workloads']!=limit or r['policy_replay']['errors']:
                        raise ValueError('invalid completed cell: '+str(candidate))
                    record=r;directory=candidate;reused=True;break
        if record is None:
            record=main.execute(data,directory,limit,True,True,False,False)
        raw=(directory/'policy_trace.txt').read_text().splitlines()
        max_cycles=max(int(line.split()[-1]) for line in raw if line.startswith('D '))
        phases=record['policy_replay'].get('phase_cycles',[])
        phase_counts={PHASES.get(i,str(i)):value for i,value in enumerate(phases) if value}
        row={'k':k,'h':h,'e':base['e'],'m':base['m'],'workloads':limit,**record['rtl_metrics'],
             'solver_jobs':record['policy_replay']['solver_jobs'],'max_solver_cycles':max_cycles,
             'phase_cycles':phase_counts,'elapsed_seconds':round(time.monotonic()-begin,2),
             'reused':reused,'evidence':str(directory.relative_to(generalize.ROOT))}
        with lock:
            rows.append(row);active.remove(name);progress()
        print(json.dumps({'state':'passed','cell':name,'completed':len(rows),'total':total,
                          'policy_cycles':row['policy_cycles'],'policy_stall':row['policy_stall'],
                          'elapsed_seconds':row['elapsed_seconds']}),flush=True)
    # Complete the previously verified baseline first, then each requested cell.
    order=sorted(((k,h) for k in ks for h in hs),key=lambda pair:(pair!=(3,3),pair))
    with ThreadPoolExecutor(max_workers=plan['workers']) as pool:
        futures={pool.submit(cell,k,h):(k,h) for k,h in order}
        for future in as_completed(futures):
            try:future.result()
            except Exception as error:
                with lock:
                    k,h=futures[future];name=f'k{k}h{h}e{base["e"]}m{base["m"]}'
                    if name in active:active.remove(name)
                    errors.append({'cell':futures[future],'error':str(error)});progress()
                print(json.dumps({'state':'failed','cell':futures[future],'error':str(error)}),flush=True)
    plot(out,rows,plan)
    save(out/'result.json',{'completed':len(rows),'requested':total,'rows':sorted(rows,key=lambda r:(r['k'],r['h'])),
        'target_policy_cycles':300000,'within_target':sum(r['policy_cycles']<=300000 for r in rows),
        'elapsed_seconds':round(time.monotonic()-started,1),'errors':errors,'manifest':'manifest.json'})
    if errors:raise RuntimeError(f'{len(errors)} campaign cells failed')
    if len(rows)!=total:raise RuntimeError('incomplete campaign')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True);parser.add_argument('--plan',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True);parser.add_argument('--reuse',type=Path,action='append',default=[])
    args=parser.parse_args()
    run(generalize.config(args.config),json.loads(args.plan.read_text()),args.out,args.reuse)
