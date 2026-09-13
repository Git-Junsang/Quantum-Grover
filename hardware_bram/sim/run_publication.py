#!/usr/bin/env python3
"""
6단계 ablation 캠페인 재현기 (RTL 사이클 축, iverilog).

    python3 run_publication.py --anchor   타깃 256 · 시드 0 하나로 6단계 사이클 정확 대조 (5회)
    python3 run_publication.py --full     500 워크로드 x 5구성 = 2,500회 + 집계
    make -C hardware_bram/sim anchor      (위와 같음)
    make -C hardware_bram/sim publication

재현 패키지 v1.0 의 04_PUBLICATION_6STAGE/scripts/run_publication.py 에서 경로만
저장소 배치로 바꿨습니다. 판정 논리와 기대값(ANCHOR, publication_report.py 의
EXPECTED)은 원본 그대로입니다.

    소스       hardware_bram/src_ablation/   공통소스 + top 5벌 + UART 브리지·데이터셋 생성기
    TB         hardware_bram/testbench/tb_publication_plusargs.v
    워크로드   hardware_bram/results/2026-09-08_publication_6stage/{seeds,workloads}.csv
    작업 폴더  $PUB_WORK (기본 /tmp/sjs_publication)

구성은 다섯인데 단계는 여섯입니다. k4h4_e1 한 빌드가 런타임 CSR 로 Normal-E1 과
K4/H4-E1 을 둘 다 내기 때문에, 로그 하나에서 사이클 값 두 개를 읽습니다.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import subprocess, csv, argparse, re, os, time, sys

HERE=Path(__file__).resolve()
HW=HERE.parents[1]                                     # hardware_bram
CORE=HW/'src_ablation'; INC=CORE; TOPS=CORE; SUP=CORE  # 공통소스·top·지원 RTL 이 한 폴더
TB=HW/'testbench/tb_publication_plusargs.v'
EVID=HW/'results/2026-09-08_publication_6stage'        # seeds.csv · workloads.csv
# 로그가 2,500개 쌓이므로 저장소 밖에 둡니다. publication_report.py 도 같은 변수를 봅니다.
WORK=Path(os.environ.get('PUB_WORK','/tmp/sjs_publication')); BUILD=WORK/'build'; LOG=WORK/'logs'; RES=WORK/'results'
ARCHS=['k4h4_e1','k4h4_e4','k3h3_e4','k3h3_e4_m1','k3h3_e4_m2']
SOURCE_NAMES=['bbht_grover_mmio.v','bbht_grover_main_ip.v','grover_arithmetic.v','grover_bbht.v','grover_checkpoint.v','grover_iteration.v','grover_loader.v','grover_measurement.v','grover_memories.v','grover_policy.v','grover_policy_impl_wrapper.v','grover_status.v']
ANCHOR={'Normal-E1':18108,'K4/H4-E1':14898,'K4/H4-E4':12209,'K3/H3-E4':11100,'K3/H3-E4-M1':9052,'K3/H3-E4-M2':7045}

def valid(p):
    return p.exists() and b'=== ALL PASS ===' in p.read_bytes()

def compile_all(force=False):
    BUILD.mkdir(parents=True,exist_ok=True); ok=True
    for a in ARCHS:
        out=BUILD/f'{a}.out'
        if out.exists() and not force: continue
        cmd=['iverilog','-g2012','-I',str(INC),'-s','tb_standalone_top','-o',str(out),str(TB),str(TOPS/f'{a}_top.v'),str(SUP/'bbht_uart_apb_bridge.v'),str(SUP/'bbht_dataset_gen.v')]+[str(CORE/x) for x in SOURCE_NAMES]
        print('COMPILE',a)
        p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        (BUILD/f'{a}_compile.log').write_text(p.stdout,errors='replace')
        if p.returncode: print('  FAIL rc=',p.returncode); ok=False
    return ok

def run_case(a,tc,si,sj,sm,log):
    tmp=log.with_suffix(log.suffix+f'.tmp.{os.getpid()}')
    cmd=['vvp',str(BUILD/f'{a}.out'),f'+TC={tc}',f'+SEED_IDX={si}',f'+SEED_J={sj}',f'+SEED_MEAS={sm}']
    with tmp.open('wb') as f: p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
    good=p.returncode==0 and valid(tmp); os.replace(tmp,log); return good,p.returncode

def cycles(p):
    txt=p.read_text(errors='replace'); return [int(x) for x in re.findall(r'cycle_count\s*=\s*(\d+)',txt)]

def anchor(jobs=5):
    LOG.mkdir(parents=True,exist_ok=True)
    row=next(csv.DictReader((EVID/'seeds.csv').open()))
    tasks=[]
    for a in ARCHS:
        p=LOG/f'{a}_tc256_s000.log'; tasks.append((a,256,0,row['seed_j'],row['seed_meas'],p))
    with ThreadPoolExecutor(max_workers=min(jobs,5)) as pool:
        fs=[pool.submit(run_case,*t) for t in tasks]
        if not all(f.result()[0] for f in fs): return False
    obs={}
    c=cycles(LOG/'k4h4_e1_tc256_s000.log'); obs['Normal-E1']=c[0]; obs['K4/H4-E1']=c[1]
    for stage,a in [('K4/H4-E4','k4h4_e4'),('K3/H3-E4','k3h3_e4'),('K3/H3-E4-M1','k3h3_e4_m1'),('K3/H3-E4-M2','k3h3_e4_m2')]: obs[stage]=cycles(LOG/f'{a}_tc256_s000.log')[1]
    ok=True
    print('===== ANCHOR target=256 seed0 =====')
    for s,e in ANCHOR.items():
        g=obs.get(s); p=(g==e); ok &= p; print(f'{s:18s} got={g} expected={e} {"PASS" if p else "FAIL"}')
    return ok

def full(jobs):
    LOG.mkdir(parents=True,exist_ok=True); RES.mkdir(parents=True,exist_ok=True)
    rows=list(csv.DictReader((EVID/'workloads.csv').open()))
    tasks=[]
    for r in rows:
        for a in ARCHS:
            log=LOG/f"{a}_tc{r['target_count']}_s{int(r['seed_index']):03d}.log"
            if not valid(log): tasks.append((a,int(r['target_count']),int(r['seed_index']),r['seed_j'],r['seed_meas'],log))
    print(f'pending={len(tasks)} / 2500 jobs={jobs}')
    failed=[]; start=time.time(); done=0
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        fs={pool.submit(run_case,*t):t for t in tasks}
        for f in as_completed(fs):
            good,rc=f.result(); done+=1
            if not good: failed.append((fs[f][0],fs[f][1],fs[f][2],rc))
            if done==1 or done%50==0 or done==len(tasks): print(f'[{done}/{len(tasks)}] failed={len(failed)} elapsed={(time.time()-start)/60:.1f}m',flush=True)
    if failed: print('FAILED',failed[:20]); return False
    p=subprocess.run([sys.executable,str(HERE.parent/'publication_report.py')])
    return p.returncode==0

ap=argparse.ArgumentParser(); g=ap.add_mutually_exclusive_group(required=True); g.add_argument('--anchor',action='store_true'); g.add_argument('--full',action='store_true'); ap.add_argument('--jobs',type=int,default=16); ap.add_argument('--rebuild',action='store_true'); args=ap.parse_args()
if not compile_all(args.rebuild): sys.exit(2)
ok=anchor(args.jobs) if args.anchor else full(args.jobs)
sys.exit(0 if ok else 1)
