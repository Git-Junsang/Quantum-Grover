#!/usr/bin/env python3
"""Compare the same Common500 prefix and reproduce the two target bins."""
from pathlib import Path
import csv
import json

OUT=Path(__file__).resolve().parent
BASE=OUT.parent/'2026-10-28_policy_parallel_paths_verified'

def rows(path):
    with path.open() as stream: return list(csv.DictReader(line for line in stream if not line.startswith('#')))

profile={key:int(value) for line in (OUT/'profile.log').read_text().splitlines()
         if line.startswith('PROFILE,') for _,key,value in [line.split(',')]}
(OUT/'profile.json').write_text(json.dumps(profile,indent=2)+'\n')
assert (OUT/'bench_profile.csv').read_bytes()==(OUT/'k3h3_e4_b3_p6/bench.csv').read_bytes()
before=rows(BASE/'k3h3_e4_b3_p6/bench.csv')
after=rows(OUT/'k3h3_e4_b3_p6/bench.csv')
assert len(before)==len(after)==1000
fields=['m','seed_idx','mode','result_index','trial','l_bbht','iter','mismatch']
for old,new in zip(before,after):
    assert all(old[key]==new[key] for key in fields),(old,new)
    if old['mode']=='normal': assert old==new
get=lambda name: profile.get('solver.run.'+name,0)
walk=get('scan_issue')+get('canon_filter')
response=sum(get(name) for name in ('scan_drain','cache_fetch','canon_memo_response','canon_finish'))
targets=[('candidate_walk_filter',34304,walk),('response_finish',46378,response)]
with (OUT/'target_comparison.csv').open('w') as stream:
    writer=csv.writer(stream)
    writer.writerow(['category','before_cycles','after_cycles','reduction_pct','speedup'])
    for name,old,new in targets:
        assert new*2<=old,(name,old,new)
        writer.writerow([name,old,new,(old-new)*100/old,old/new])
result={'matching_rows':1000,'matching_fields':fields,'normal_rows_unchanged':True,
        'target_bins_halved':True,'target_cycles':{name:new for name,old,new in targets}}
(OUT/'comparison.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
