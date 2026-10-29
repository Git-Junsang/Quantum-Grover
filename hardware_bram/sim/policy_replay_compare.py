#!/usr/bin/env python3
"""Controlled old/new policy RTL latency comparison on identical Main-IP jobs.

This is standalone solver timing, not a counterfactual full-system simulation.
Every output, including cost/segment/tuple ties, is checked against the exact
reference. Both revisions receive the same slot order and accepted requests.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

import generalize as g
import generalize_main as main
import dse

def run(data,trace,old_rtl,out):
    if not 1<=data['k']<=5 or not 1<=data['h']<=8:
        raise ValueError('scalar replay harness supports capacity 1..5 and lookahead 1..8')
    out=out.resolve();out.mkdir(parents=True,exist_ok=True)
    vectors=[]
    for line in trace.read_text().splitlines():
        if not line.startswith('S '):continue
        _,cycle,job,spec,epoch,valid,slots,window=line.split()
        mask=int(valid,16);flat=int(slots,16);raw=int(window,16)
        held=tuple(sorted((flat>>(7*i))&127 for i in range(data['k']) if mask>>i&1))
        requests=tuple((raw>>(7*i))&127 for i in range(data['h']+1))
        source,chosen,cost,segments=g.oracle(held,requests,data['k'],data['policy_mode'])
        vectors.append(f'{mask:x} {flat:x} {g.pack(requests):x} {source} {len(chosen)} {g.pack(chosen):x} {cost} {segments}')
    (out/'vectors.txt').write_text('\n'.join(vectors)+'\n')
    results={}
    for name,policy in [('before',old_rtl),('after',g.ROOT/'hardware_bram/src/grover_policy_parameterized.sv')]:
        directory=out/name;directory.mkdir(exist_ok=True)
        sources=[policy,g.ROOT/'hardware_bram/src/grover_policy.v',g.ROOT/'hardware_bram/src/grover_param.vh',
                 g.ROOT/'hardware_bram/testbench/tb_policy_replay.cpp']
        inputs={'config':data,'sha256':{str(p):dse.digest(p) for p in sources},'vectors_sha256':dse.digest(out/'vectors.txt')}
        if (directory/'manifest.json').exists() and json.loads((directory/'manifest.json').read_text())!=inputs:
            raise ValueError('replay inputs changed; use a new directory')
        main.save(directory/'manifest.json',inputs)
        source=directory/'source';source.mkdir(exist_ok=True)
        for path in sources:shutil.copy2(path,source/path.name)
        key=hashlib.sha256(json.dumps(inputs,sort_keys=True).encode()).hexdigest()[:20]
        build=Path('/tmp')/('bbht_policy_replay_'+key)
        build.mkdir(exist_ok=True)
        binary=build/'replay'
        if not binary.exists():
            main.run(['verilator','--cc','--exe','--build','-j','1','-Wno-fatal','--assert',
                '--Mdir',build,'--top-module','grover_ckpt_policy_parameterized',
                f'-GCHECKPOINT_CAPACITY={data["k"]}',f'-GLOOKAHEAD_SHOTS={data["h"]}',
                f'-GEXACT_PRUNE={data["policy_mode"]}','-GFORCE_GENERIC=1','-GSCAN_LANES=4',
                '-GMEMO_ADDR_W=12','-GCOUNT_W=3','-CFLAGS','-O2','-I'+str(source),
                source/'grover_policy.v',source/'grover_policy_parameterized.sv',source/'tb_policy_replay.cpp',
                '-o','replay'],directory/'build.log')
        with (directory/'rows.csv').open('w') as stream:
            main.run([binary,out/'vectors.txt'],directory/'simulation.log',stdout=stream,timeout=300)
        rows=list(csv.DictReader((directory/'rows.csv').open()))
        if len(rows)!=len(vectors):raise ValueError('replay did not finish all solver jobs')
        results[name]={field:sum(int(r[field]) for r in rows) for field in ('cycles','actions','hits','misses')}
        results[name]['max_cycles']=max(int(r['cycles']) for r in rows)
    result={'config':data,'solver_jobs':len(vectors),'results':results,'errors':0,
            'scope':'identical-input standalone RTL solver clocks; not full-system before/after'}
    main.save(out/'result.json',result);print(json.dumps(result),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True);parser.add_argument('--trace',type=Path,required=True)
    parser.add_argument('--old-rtl',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();run(g.config(args.config),args.trace.resolve(),args.old_rtl.resolve(),args.out)
