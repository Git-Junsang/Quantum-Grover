#!/usr/bin/env python3
"""Maximum port-width smoke with a deliberately simple, independent oracle.

All 16384 entries match, so both modes must finish their first j=0 shot from
uniform amplitudes. This is not a Common500 performance measurement.
"""
from pathlib import Path
import csv,hashlib,json,os,sys,struct
import numpy as np
ROOT=Path('/workspace');sys.path.insert(0,str(ROOT/'hardware_bram/sim'))
sys.path.insert(0,str(ROOT/'software/reference_model_develop/models'))
sys.path.insert(0,str(ROOT/'software/reference_model_develop/models/rtl_reference_model'))
sys.path.insert(0,str(ROOT/'software/reference_model_develop/models/common'))
import generalize_main as g
import dse
from rtl_reference_model.checkpoint_bbht_model import V098MeasurementRandomSource,measure_v098_state
OUT=Path(__file__).resolve().parent/'maximum_width_final'
data=json.loads((ROOT/'hardware_bram/sim/generalize_config.json').read_text())|{'k':10,'h':10,'e':16,'m':4}
manifest=g.prepare(data,OUT,1,True,True)
source=OUT/'source';build=Path('/tmp')/('bbht_general_max_'+hashlib.sha256(str(OUT).encode()).hexdigest()[:16]);build.mkdir(exist_ok=True);obj=build/'obj'
workload=OUT/'workload'
if not workload.exists():g.run([sys.executable,ROOT/'software/reference_model_develop/tb_stimulus/dump_bench_workload.py','--seeds','100','--out',workload],OUT/'workload_build.log')
(workload/'data_m1.bin').write_bytes(struct.pack('<h',12345)*16384)
defines=['-DBBHT_HOST_TEST','-DBBHT_NO_PRINTF','-DBBHT_TIMEOUT=200000000']
g.run(['gcc','-c','-O2',*defines,'-I',source,source/'bbht_grover_driver.c','-o',build/'driver.o'],OUT/'driver_build.log')
rtl=[source/(name+('.sv' if name in dse.SV_CORE else '.v')) for name in dse.COMM+dse.CORE]
g.run(['verilator','--cc','--exe','--build','-j','2','-Wno-fatal','-Wno-DECLFILENAME','--assert','--Mdir',obj,
    '-CFLAGS',' '.join(defines+[f'-I{source}','-O2']),'-LDFLAGS',build/'driver.o','-I'+str(source),*rtl,
    source/'adapter.v','--top-module','bbht_rvx_wrapper',source/'tb_bench500.cpp','-o','bench'],OUT/'build.log',cwd=build)
with (OUT/'bench.csv').open('w') as stream:
    g.run([obj/'bench','+POLICY_TRACE='+str(OUT/'policy_trace.txt')],OUT/'simulation.log',
        env=os.environ|{'WL_DIR':str(workload),'BENCH_LIMIT':'1'},stdout=stream,timeout=180)
rows=list(csv.DictReader(line for line in (OUT/'bench.csv').read_text().splitlines() if not line.startswith('#')))
seed_j,seed_meas=map(int,(workload/'seeds.txt').read_text().splitlines()[0].split())
golden=measure_v098_state(np.full(16384,32768,dtype=np.int64),np.ones(16384,dtype=np.bool_),V098MeasurementRandomSource(seed_meas))
assert len(rows)==2
for row in rows:
    assert int(row['result_index'])==golden.result_index and int(row['trial'])==1 and int(row['l_bbht'])==0 and int(row['iter'])==0 and int(row['mismatch'])==0,row
trace=g.validate_trace(OUT/'policy_trace.txt',data)
stream=dse.kh.generate_stream(seed_j,12)
for line in (OUT/'policy_trace.txt').read_text().splitlines():
    if line.startswith('S '):
        fields=line.split();offset=int(fields[3]);window=int(fields[7],16)
        assert tuple((window>>(7*i))&127 for i in range(11))==stream[offset:offset+11]
record={'config':data,'scope':'synthetic all-targets j=0 maximum-width smoke; not Common500 performance',
    'golden_uniform_index':golden.result_index,'input_data_sha256':dse.digest(workload/'data_m1.bin'),
    'policy_replay':trace,'request_window_bits':77,'tuple_bits':70,'errors':0}
g.save(OUT/'result.json',record);print(json.dumps(record),flush=True)
