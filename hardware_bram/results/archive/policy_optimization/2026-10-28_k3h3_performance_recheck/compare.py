#!/usr/bin/env python3
"""Compare exact Common500 execution with two matching K3/H3 baselines."""
from pathlib import Path
import csv
import json

OUT=Path(__file__).resolve().parent
RESULTS=OUT.parent
VERSIONS=[
    ('before_build_cache',RESULTS/'2026-10-28_policy_gap_bound_final'),
    ('previous',RESULTS/'2026-10-28_policy_parallel_paths_verified'),
]
fields=['policy_cycles','policy_stall','cycles']
invariants=['m','seed_idx','mode','result_index','trial','l_bbht','iter','mismatch']
current=json.loads((OUT/'sim.json').read_text())
def rows(path):
    with path.open() as stream:
        return list(csv.DictReader(line for line in stream if not line.startswith('#')))
latest=rows(OUT/'bench.csv')
assert len(latest)==1000
comparisons={}
for name,directory in VERSIONS:
    metrics=json.loads((directory/'k3h3_e4_b3_p6/sim.json').read_text())
    baseline=rows(directory/'k3h3_e4_b3_p6/bench.csv')
    assert len(baseline)==len(latest)
    for old,new in zip(baseline,latest):
        assert all(old[key]==new[key] for key in invariants),(name,old,new)
        if old['mode']=='normal': assert old==new
    comparisons[name]={key:{'before':metrics[key],'after':current[key],
        'saved_cycles':metrics[key]-current[key],
        'reduction_pct':100*(metrics[key]-current[key])/metrics[key]}
        for key in fields}
with (OUT/'comparison.csv').open('w') as stream:
    writer=csv.writer(stream)
    writer.writerow(['baseline','metric','before','after','saved_cycles','reduction_pct'])
    for name,values in comparisons.items():
        for key,result in values.items(): writer.writerow([name,key,*result.values()])
result={'configuration':{'k':3,'h':3,'e':4,'build_rows':3,'prune':6,'workloads':500},
        'matching_rows':1000,'normal_rows_identical':True,'matching_invariants':invariants,
        'physical_iterations':current['iter'],
        'stall_share_of_execution_pct':100*current['policy_stall']/current['cycles'],
        'comparisons':comparisons,
        'note':'Integrated accelerator RTL cycles; full-SoC console verification is a separate same-source run.'}
(OUT/'comparison.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
