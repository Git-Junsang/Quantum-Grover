#!/usr/bin/env python3
"""
6단계 ablation 로그 2,500개를 집계해 기대 총합과 맞댑니다.

    python3 publication_report.py        (run_publication.py --full 이 끝에 부릅니다)

로그는 $PUB_WORK/logs (기본 /tmp/sjs_publication/logs) 에서 읽고, 집계는
$PUB_WORK/results/ 에 씁니다. 판정은 세 가지가 전부 맞아야 PASS 입니다.

    관측 3,000개 (500 워크로드 x 6단계) 가 빠짐없이 있다
    한 워크로드 안에서 여섯 단계의 result_index · trial_count · L_BBHT 가 같다
    단계별 사이클 총합이 EXPECTED 와 정확히 같다

EXPECTED 는 hardware_bram/results/2026-09-08_publication_6stage/summary.csv 의
총합과 같은 값입니다. 재현 패키지 v1.0 의 postprocess_portable.py 에서 경로만
바꿨습니다.
"""
from pathlib import Path
import csv,re,statistics,math,sys,os
HW=Path(__file__).resolve().parents[1]
WORK=Path(os.environ.get('PUB_WORK','/tmp/sjs_publication')); LOG=WORK/'logs'; RES=WORK/'results'; RES.mkdir(parents=True,exist_ok=True)
ARCHS=['k4h4_e1','k4h4_e4','k3h3_e4','k3h3_e4_m1','k3h3_e4_m2']
STAGES=[('Normal-E1','k4h4_e1',0),('K4/H4-E1','k4h4_e1',1),('K4/H4-E4','k4h4_e4',1),('K3/H3-E4','k3h3_e4',1),('K3/H3-E4-M1','k3h3_e4_m1',1),('K3/H3-E4-M2','k3h3_e4_m2',1)]
EXPECTED={'Normal-E1':42308335,'K4/H4-E1':18349320,'K4/H4-E4':11246755,'K3/H3-E4':10385795,'K3/H3-E4-M1':8500620,'K3/H3-E4-M2':6890470}
def vals(txt,key): return [int(x) for x in re.findall(rf'{re.escape(key)}\s*=\s*(\d+)',txt)]
def p95(v): s=sorted(v); return s[max(0,math.ceil(.95*len(s))-1)]
rows=list(csv.DictReader((HW/'results/2026-09-08_publication_6stage/workloads.csv').open())); obs=[]; semantic_fail=[]; bad=[]
for w in rows:
 tc=int(w['target_count']); si=int(w['seed_index']); chosen=[]
 for stage,a,mi in STAGES:
  p=LOG/f'{a}_tc{tc}_s{si:03d}.log'
  if not p.exists(): bad.append((a,tc,si,'MISSING')); chosen=[]; break
  t=p.read_text(errors='replace')
  if '=== ALL PASS ===' not in t: bad.append((a,tc,si,'NO_PASS')); chosen=[]; break
  d={k:vals(t,k) for k in ['result_index','trial_count','L_BBHT','actual_iter','cycle_count']}
  if any(len(x)<2 for x in d.values()): bad.append((a,tc,si,'METRIC')); chosen=[]; break
  chosen.append((stage,{k:v[mi] for k,v in d.items()}))
 if not chosen: continue
 ref=chosen[0][1]; sem=all(x['result_index']==ref['result_index'] and x['trial_count']==ref['trial_count'] and x['L_BBHT']==ref['L_BBHT'] for _,x in chosen)
 if not sem: semantic_fail.append((tc,si))
 for stage,x in chosen: obs.append({'target_count':tc,'seed_index':si,'stage':stage,'cycles':x['cycle_count'],'actual_iter':x['actual_iter'],'semantic_equal':int(sem)})
fields=['target_count','seed_index','stage','cycles','actual_iter','semantic_equal']
with (RES/'stage_observations.csv').open('w',newline='') as f: w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(obs)
summary=[]
for s,_,_ in STAGES:
 rr=[x for x in obs if x['stage']==s]; cyc=[x['cycles'] for x in rr]; total=sum(cyc)
 summary.append({'stage':s,'n':len(cyc),'total_cycles':total,'mean_cycles':statistics.mean(cyc) if cyc else 0,'median_cycles':statistics.median(cyc) if cyc else 0,'p95_cycles':p95(cyc) if cyc else 0,'aggregate_speedup_vs_Normal':EXPECTED['Normal-E1']/total if total else 0,'expected_total':EXPECTED[s],'exact_match':int(total==EXPECTED[s])})
with (RES/'publication_6stage_summary_reproduced.csv').open('w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=summary[0].keys()); w.writeheader(); w.writerows(summary)
print('===== PUBLICATION REPRO SUMMARY ====='); ok=(len(obs)==3000 and not bad and not semantic_fail)
for r in summary:
 p=bool(r['exact_match']); ok &= p; print(f"{r['stage']:18s} total={r['total_cycles']:10d} expected={r['expected_total']:10d} {'PASS' if p else 'FAIL'}")
print('observations',len(obs),'/3000','bad',len(bad),'semantic_fail',len(semantic_fail))
print('FINAL', 'PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)
