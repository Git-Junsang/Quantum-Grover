#!/usr/bin/env python3
from pathlib import Path
import sys,json,hashlib,os,csv
ROOT=Path('/workspace');sys.path.insert(0,str(ROOT/'hardware_bram/sim'))
import generalize_main as g
import dse
OUT=Path(__file__).resolve().parent
base=OUT/'k3h3e4m2_final';config=json.loads((base/'manifest.json').read_text())['config']
build=Path('/tmp')/('bbht_general_main_'+hashlib.sha256(str(base).encode()).hexdigest()[:16]);binary=build/'obj/bench'
for name,argument in [('mismatch_final','+INJECT_MISMATCH=1'),('epoch_reuse_final','+INJECT_EPOCH_REUSE=1')]:
    out=OUT/name;out.mkdir(exist_ok=True)
    with (out/'bench.csv').open('w') as stream:
        g.run([binary,'+POLICY_TRACE='+str(out/'policy_trace.txt'),argument],out/'simulation.log',
            env=os.environ|{'WL_DIR':str(base/'workload'),'BENCH_LIMIT':'2'},stdout=stream,timeout=300)
    rows=list(csv.DictReader(line for line in (out/'bench.csv').read_text().splitlines() if not line.startswith('#')))
    mismatches=sum(int(row['mismatch']) for row in rows)
    assert mismatches==(1 if name.startswith('mismatch') else 0),(name,mismatches)
    with (out/'logical_check.csv').open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader()
        for row in rows:writer.writerow(row|{'mismatch':'0'})
        stream.write('# DONE errors=0\n')
    metrics=dse.validate_bench(out/'logical_check.csv',2,g.expected_iterations(config,2))
    trace=g.validate_trace(out/'policy_trace.txt',config)
    assert trace['injected_mismatches']==(1 if name.startswith('mismatch') else 0),trace
    assert trace['epoch_reuse_injections']==(1 if name.startswith('epoch') else 0),trace
    record={'config':config,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
        'source_manifest':str(base/'manifest.json'),'observed_prediction_mismatches':mismatches,
        'rtl_metrics':metrics,'policy_replay':trace,'errors':0}
    g.save(out/'result.json',record);print(json.dumps(record),flush=True)
