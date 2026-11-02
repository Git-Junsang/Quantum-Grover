#!/usr/bin/env python3
"""One numeric configuration for parameterized RTL development checks.

Default stages exercise the standalone solver and parallel datapath blocks.
The explicit main stage invokes the real-driver Main-IP integration runner.
Neither path establishes full-SoC implementation or board timing.
"""
from __future__ import annotations
import argparse
import functools
import hashlib
import json
import random
import subprocess
import shutil
from pathlib import Path
import kh_sweep as reference

ROOT=Path(__file__).resolve().parents[2]

def config(path):
    data=json.loads(path.read_text())
    required={'schema','k','h','e','m','policy_mode','scan_lanes','force_generic'}
    if set(data)!=required or data['schema']!=2:
        raise ValueError(f'schema 2 requires exactly {sorted(required)}')
    for key,low,high in [('k',1,10),('h',1,10),('e',1,16),('m',1,4)]:
        if type(data[key]) is not int or not low<=data[key]<=high:
            raise ValueError(f'{key} must be an integer in {low}..{high}')
    if data['policy_mode'] not in (5,6) or type(data['policy_mode']) is not int:
        raise ValueError('policy_mode must be 5 or 6')
    if data['scan_lanes'] not in (1,2,4) or type(data['scan_lanes']) is not int:
        raise ValueError('scan_lanes must be 1, 2 or 4')
    if type(data['force_generic']) is not bool:
        raise ValueError('force_generic must be boolean')
    return data

def oracle(held,window,k,mode):
    """Independent exhaustive memoized DP, including the frozen root tie-break."""
    held=tuple(sorted(held));pool=tuple(dict.fromkeys(window))
    @functools.cache
    def tail(state,depth):
        if depth==len(window):return 0
        request=window[depth];source=max((0,*(v for v in state if v<=request)))
        children=reference.next_states(k,state,source,request,pool)
        return request-source+min(tail(child,depth+1) for child in children)
    request=window[0];source=max((0,*(v for v in held if v<=request)))
    children=reference.next_states(k,held,source,request,pool)
    if mode==6 and len(children)==1:
        child=children[0];return source,child,request-source,1
    cost,segments,child=min((request-source+tail(child,1),
        1+sum(source<v<request for v in child),child) for child in children)
    return source,child,cost,segments

def pack(values):return sum(v<<(7*i) for i,v in enumerate(values))

def vectors(k,h,count,seed,mode):
    rng=random.Random(seed)
    directed=[((),tuple([0]*(h+1))),
        (tuple(range(k)),tuple([0,127]+[0]*(h-1))),
        (tuple(range(k)),tuple([min(127,k+2),1]+[min(127,k+1)]*(h-1))),
        (tuple(range(k)),tuple((i*3+1)%17 for i in range(h+1))),
        (tuple(range(k)),tuple(k+i for i in range(h+1)))]
    for index in range(count):
        # Small-value cases still use all parameter widths, create repeated
        # subproblems, and keep the independent exhaustive oracle affordable.
        maximum=16 if k<=4 and h<=4 else 7
        size=rng.randrange(min(k,maximum+1)+1)
        held=tuple(sorted(rng.sample(range(maximum+1),size)))
        window=tuple(rng.randrange(maximum+1) for _ in range(h+1))
        directed.append((held,window))
    result=[]
    for held,window in directed:
        source,child,cost,segments=oracle(held,window,k,mode)
        # Randomize physical slot order; the policy operates on a set.
        physical=[0]*k;valid=0
        for slot,value in zip(rng.sample(range(k),len(held)),held):
            physical[slot]=value;valid|=1<<slot
        result.append(f'{valid:x} {pack(physical):x} {pack(window):x} '
            f'{source} {len(child)} {pack(child):x} {cost} {segments}')
    return result

def run(data,out,count=32,seed=28028):
    out.mkdir(parents=True,exist_ok=True)
    sources=[ROOT/'hardware_bram/src'/name for name in
             ('grover_policy.v','grover_policy_parameterized.sv','grover_param.vh')]
    sources.append(ROOT/'hardware_bram/testbench/tb_policy_parameterized.sv')
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    manifest={'config':data,'sha256':hashes,'random_cases':count,'seed':seed,
        'scope':'standalone RTL policy only; full Main-IP integration pending',
        'backend':'production' if not data['force_generic'] and data['k'] in (3,4) and data['h']<=8 else 'generic experimental'}
    path=out/'manifest.json'
    if path.exists() and json.loads(path.read_text())!=manifest:
        raise ValueError('inputs changed; use a new output directory')
    path.write_text(json.dumps(manifest,indent=2)+'\n')
    snapshot=out/'source';snapshot.mkdir(exist_ok=True)
    for source in sources:shutil.copy2(source,snapshot/source.name)
    trace=out/'vectors.txt';trace.write_text('\n'.join(vectors(data['k'],data['h'],count,seed,data['policy_mode']))+'\n')
    binary=out/'policy.vvp';top='tb_policy_parameterized'
    args={'K':data['k'],'H':data['h'],'MODE':data['policy_mode'],
        'FORCE_GENERIC':int(data['force_generic']),'LANES':data['scan_lanes']}
    command=['iverilog','-g2012','-I'+str(snapshot),'-s',top,
        *(f'-P{top}.{k}={v}' for k,v in args.items()),'-o',str(binary),
        str(snapshot/sources[0].name),str(snapshot/sources[1].name),str(snapshot/sources[-1].name)]
    with (out/'compile.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
    with (out/'simulation.log').open('w') as log:
        subprocess.run(['vvp',str(binary),'+TRACE='+str(trace.resolve())],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=300)
    summaries=[line for line in (out/'simulation.log').read_text().splitlines() if line.startswith('SUMMARY')]
    if len(summaries)!=1 or 'errors=0' not in summaries[0]:raise ValueError('missing successful RTL summary')
    result=manifest|{'summary':summaries[0],'cycles_are':'observed start-to-done RTL clock edges, cross-checked with hardware counter'}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(summaries[0],flush=True)
    return result

def run_parallel(data,out):
    """Verify independent parameter-sized blocks for this same configuration."""
    out.mkdir(parents=True,exist_ok=True)
    names=('grover_parallel.sv','grover_arithmetic.v','grover_measurement.v','grover_memories.v','grover_param.vh')
    sources=[ROOT/'hardware_bram/src'/name for name in names]
    sources.append(ROOT/'hardware_bram/testbench/tb_parallel_generalized.sv')
    manifest={'k':data['k'],'e':data['e'],'m':data['m'],
        'scope':'independent memory/iteration/square RTL blocks; Main IP integration pending',
        'sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    path=out/'manifest.json'
    if path.exists() and json.loads(path.read_text())!=manifest:
        raise ValueError('inputs changed; use a new output directory')
    path.write_text(json.dumps(manifest,indent=2)+'\n')
    snapshot=out/'source';snapshot.mkdir(exist_ok=True)
    for source in sources:shutil.copy2(source,snapshot/source.name)
    top='tb_parallel_generalized';binary=out/'parallel.vvp'
    command=['iverilog','-g2012','-I'+str(snapshot),'-s',top,
        f'-P{top}.K={data["k"]}',f'-P{top}.E={data["e"]}',f'-P{top}.M={data["m"]}',
        '-o',str(binary),*(str(snapshot/p.name) for p in sources if p.suffix!='.vh')]
    with (out/'compile.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
    summaries=[]
    for pattern in (0,1):
        log_path=out/('simulation.log' if pattern==0 else 'saturation.log')
        with log_path.open('w') as log:
            subprocess.run(['vvp',str(binary),f'+EXTREME={pattern}'],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
        lines=[line for line in log_path.read_text().splitlines() if line.startswith('SUMMARY')]
        if len(lines)!=1 or 'errors=0' not in lines[0]:raise ValueError('missing successful parallel RTL summary')
        summaries.extend(lines)
    result=manifest|{'summary':summaries[0],'saturation_summary':summaries[1]}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(summaries[0],flush=True)
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--random-cases',type=int,default=32)
    parser.add_argument('--seed',type=int,default=28028)
    parser.add_argument('--stages',default='policy,parallel',help='policy,parallel,main; main runs a short integrated driver/Enumeration check')
    args=parser.parse_args()
    if args.random_cases<0:parser.error('--random-cases cannot be negative')
    data=config(args.config);out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    stages=args.stages.split(',')
    if len(set(stages))!=len(stages) or not set(stages)<={'policy','parallel','main'}:
        parser.error('--stages must contain policy, parallel and/or main, without duplicates')
    results={'config':data,'integration':'pending: standalone blocks do not establish integrated cycles or policy stall'}
    for stage in stages:
        if stage=='main':
            from generalize_main import execute
            results[stage]=execute(data,out/'main',limit=2)
            results['integration']='Main IP integration smoke passed; full Common500 remains separate'
        elif stage=='policy':results[stage]=run(data,out/'policy',args.random_cases,args.seed)
        else:results[stage]=run_parallel(data,out/'parallel')
    (out/'result.json').write_text(json.dumps(results,indent=2)+'\n')
