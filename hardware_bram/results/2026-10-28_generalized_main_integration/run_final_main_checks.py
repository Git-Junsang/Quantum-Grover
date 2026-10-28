#!/usr/bin/env python3
from pathlib import Path
import json,sys
ROOT=Path('/workspace');sys.path.insert(0,str(ROOT/'hardware_bram/sim'))
import generalize_main
OUT=Path(__file__).resolve().parent/'final_boundaries'
OUT.mkdir(exist_ok=True)
base=json.loads((ROOT/'hardware_bram/sim/generalize_config.json').read_text())
for name,k,h,e,m in [('k5h3e3m4',5,3,3,4),('k3h9e1m1',3,9,1,1),
                    ('k10h2e16m3',10,2,16,3),('k1h10e1m4',1,10,1,4)]:
    config=base|{'k':k,'h':h,'e':e,'m':m}
    (OUT/(name+'.json')).write_text(json.dumps(config,indent=2)+'\n')
    print('START',name,flush=True)
    generalize_main.execute(config,OUT/name,2,True,True,False,True)
print('ALL MAIN BOUNDARY CHECKS PASSED',flush=True)
