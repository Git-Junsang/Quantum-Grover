#!/usr/bin/env python3
"""
K/H 단독 실험 재현기 -- E1 · M1=0 · M2=0 에서 체크포인트 개수 K 와 정책 지평 H 만
바꾼 세 구성(K4/H4 대조군 · K3/H4 · K3/H3)을 250 워크로드씩, 750회 돌립니다.

    python3 run_kh.py [--jobs N]
    make -C hardware_bram/sim kh

통과 조건은 구성별 사이클 총합이 EXPECT 와 정확히 같고, 세 구성의 논리 궤적
(result_index · trial_count · L_BBHT)이 워크로드마다 같은 것입니다. 기대값은
hardware_bram/results/2026-09-09_kh_isolated_e1/summary.csv 와 같습니다.

재현 패키지 v1.0 의 05_KH_ISOLATED/scripts/run_kh.py 에서 경로만 바꿨습니다.
소스·TB 는 6단계 ablation 과 같은 것을 쓰고 top 만 다릅니다. TB 가 표시하는
문자열에 k4h4 가 하드코딩으로 남아 있지만 실제 파라미터는 top 이 정합니다.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,csv,re,os,argparse,sys
HW=Path(__file__).resolve().parents[1]                 # hardware_bram
CORE=HW/'src_ablation'; INC=CORE; TOPS=CORE; SUP=CORE; TB=HW/'testbench/tb_publication_plusargs.v'
WORK=Path(os.environ.get('KH_WORK','/tmp/sjs_kh')); BUILD=WORK/'build'; LOG=WORK/'logs'; RES=WORK/'results'
ARCHS=['k4h4_e1_control','k3h4_e1','k3h3_e1']; EXPECT={'k4h4_e1_control':8836298,'k3h4_e1':8818101,'k3h3_e1':8596609}
SRC=['bbht_grover_mmio.v','bbht_grover_main_ip.v','grover_arithmetic.v','grover_bbht.v','grover_checkpoint.v','grover_iteration.v','grover_loader.v','grover_measurement.v','grover_memories.v','grover_policy.v','grover_policy_impl_wrapper.v','grover_status.v']
def valid(p): return p.exists() and b'=== ALL PASS ===' in p.read_bytes()
def compile_all(force=False):
 BUILD.mkdir(parents=True,exist_ok=True); ok=True
 for a in ARCHS:
  out=BUILD/f'{a}.out'
  if out.exists() and not force: continue
  cmd=['iverilog','-g2012','-I',str(INC),'-s','tb_standalone_top','-o',str(out),str(TB),str(TOPS/f'{a}_top.v'),str(SUP/'bbht_uart_apb_bridge.v'),str(SUP/'bbht_dataset_gen.v')]+[str(CORE/x) for x in SRC]
  p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True); (BUILD/f'{a}_compile.log').write_text(p.stdout,errors='replace'); ok &= p.returncode==0
 return ok
def run(t):
 a,tc,si,sj,sm,log=t; tmp=log.with_suffix(log.suffix+f'.tmp.{os.getpid()}'); cmd=['vvp',str(BUILD/f'{a}.out'),f'+TC={tc}',f'+SEED_IDX={si}',f'+SEED_J={sj}',f'+SEED_MEAS={sm}']
 with tmp.open('wb') as f:p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
 g=p.returncode==0 and valid(tmp); os.replace(tmp,log); return g
def parse(p):
 t=p.read_text(errors='replace'); d={k:[int(x) for x in re.findall(rf'{k}\s*=\s*(\d+)',t)] for k in ['result_index','trial_count','L_BBHT','cycle_count']}; return {k:v[1] for k,v in d.items()}
ap=argparse.ArgumentParser(); ap.add_argument('--jobs',type=int,default=16); ap.add_argument('--rebuild',action='store_true'); args=ap.parse_args()
if not compile_all(args.rebuild): sys.exit(2)
LOG.mkdir(parents=True,exist_ok=True); RES.mkdir(parents=True,exist_ok=True); rows=list(csv.DictReader((HW/'results/2026-09-09_kh_isolated_e1/workloads.csv').open())); tasks=[]
for r in rows:
 for a in ARCHS:
  p=LOG/f"{a}_tc{r['target_count']}_s{int(r['seed_index']):03d}.log"; 
  if not valid(p): tasks.append((a,int(r['target_count']),int(r['seed_index']),r['seed_j'],r['seed_meas'],p))
with ThreadPoolExecutor(max_workers=args.jobs) as pool:
 fs=[pool.submit(run,t) for t in tasks]; failed=sum(not f.result() for f in as_completed(fs))
if failed: print('run failures',failed); sys.exit(1)
agg={a:0 for a in ARCHS}; semfail=0
for r in rows:
 vals={a:parse(LOG/f"{a}_tc{r['target_count']}_s{int(r['seed_index']):03d}.log") for a in ARCHS}
 for a in ARCHS: agg[a]+=vals[a]['cycle_count']
 ref=vals[ARCHS[0]]
 if any((v['result_index'],v['trial_count'],v['L_BBHT'])!=(ref['result_index'],ref['trial_count'],ref['L_BBHT']) for v in vals.values()): semfail+=1
out=[]; ok=(semfail==0)
for a in ARCHS:
 p=agg[a]==EXPECT[a]; ok &= p; out.append({'architecture':a,'runs':250,'aggregate_cycles':agg[a],'expected_cycles':EXPECT[a],'exact_match':int(p)}); print(a,agg[a],EXPECT[a],'PASS' if p else 'FAIL')
with (RES/'kh_e1_summary_reproduced.csv').open('w',newline='') as f:w=csv.DictWriter(f,fieldnames=out[0].keys());w.writeheader();w.writerows(out)
print('semantic mismatch',semfail); print('FINAL','PASS' if ok else 'FAIL'); sys.exit(0 if ok else 1)
