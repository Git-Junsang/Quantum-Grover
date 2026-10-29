#!/usr/bin/env python3
"""Reproduce directed solver checks against the exhaustive RTL reference."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

OUT=Path(__file__).resolve().parent
SRC=OUT/'source'
CASES={
    'seed_mode5': {},
    'seed_mode6': {'EXACT_PRUNE':6},
    'lanes1': {'CANON_LANES':1},
    'lanes2': {'CANON_LANES':2},
    'scan1_canon4': {'SCAN_LANES':1},
    'horizon1': {'LOOKAHEAD_SHOTS':1,'RANDOM_CASES':32,'REQUIRE_COVERAGE':0,'EXACT_PRUNE':6},
    'horizon2': {'LOOKAHEAD_SHOTS':2,'RANDOM_CASES':64,'REQUIRE_COVERAGE':0},
    'k3h4': {'LOOKAHEAD_SHOTS':4,'RANDOM_CASES':64},
    'k4h4': {'CHECKPOINT_CAPACITY':4,'LOOKAHEAD_SHOTS':4,'RANDOM_CASES':64},
    'k4h8_mode5': {'CHECKPOINT_CAPACITY':4,'LOOKAHEAD_SHOTS':8,'RANDOM_CASES':32},
    'k4h8_mode6': {'CHECKPOINT_CAPACITY':4,'LOOKAHEAD_SHOTS':8,'RANDOM_CASES':32,'EXACT_PRUNE':6},
    'k4h8_lanes1': {'CHECKPOINT_CAPACITY':4,'LOOKAHEAD_SHOTS':8,'RANDOM_CASES':8,'CANON_LANES':1},
    'k4h8_lanes2': {'CHECKPOINT_CAPACITY':4,'LOOKAHEAD_SHOTS':8,'RANDOM_CASES':8,'CANON_LANES':2},
    'k4h8_scan1_canon4': {'CHECKPOINT_CAPACITY':4,'LOOKAHEAD_SHOTS':8,'RANDOM_CASES':8,'SCAN_LANES':1},
}

def check(item):
    name,parameters=item
    top='tb_policy_seed_replay'
    if name=='single_action': top='tb_policy_single_action'
    with tempfile.TemporaryDirectory(prefix='policy_parallel_') as tmp:
        command=['iverilog','-g2012','-I'+str(SRC),'-s',top]
        command += [f'-P{top}.{key}={value}' for key,value in parameters.items()]
        command += ['-o',tmp+'/test.vvp',str(SRC/'grover_policy.v'),str(SRC/(top+'.sv'))]
        with (OUT/(name+'.log')).open('w') as log:
            subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
            subprocess.run(['vvp',tmp+'/test.vvp'],stdout=log,stderr=subprocess.STDOUT,check=True)
        text=(OUT/(name+'.log')).read_text()
        assert 'errors=0' in text, name
        return name,{'parameters':parameters,'command':command[:-3],
                     'summary':[line for line in text.splitlines() if line.startswith(('SUMMARY','CERTIFICATES'))]}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case',action='append',choices=[*CASES,'single_action'])
    args=parser.parse_args()
    inputs=['grover_policy.v','grover_param.vh','tb_policy_seed_replay.sv','tb_policy_single_action.sv']
    (OUT/'unit_source_sha256.json').write_text(json.dumps({name:hashlib.sha256((SRC/name).read_bytes()).hexdigest()
        for name in inputs},indent=2)+'\n')
    selected=args.case or [*CASES,'single_action']
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=dict(pool.map(check,[(name,CASES.get(name,{})) for name in selected]))
    path=OUT/'unit_results.json'
    if args.case and path.exists(): results=json.loads(path.read_text())|results
    (OUT/'unit_results.json').write_text(json.dumps(results,indent=2)+'\n')
    for name,result in results.items(): print(name, *result['summary'],sep='\n')
