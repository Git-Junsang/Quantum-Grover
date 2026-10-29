#!/usr/bin/env python3
"""Check non-power-of-two tails, wide slots, independent E/M, and exact arithmetic."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
# Unit reruns write to a fresh temporary directory. The archived block results
# remain evidence for the source revision that originally produced them.
OUT=Path(tempfile.mkdtemp(prefix='bbht_parallel_unit_'))

class ParallelDatapathTests(unittest.TestCase):
    def test_rows_and_arithmetic(self):
        sources=[ROOT/'hardware_bram/src'/name for name in
            ('grover_parallel.sv','grover_arithmetic.v','grover_measurement.v','grover_memories.v','grover_param.vh')]
        sources.append(ROOT/'hardware_bram/testbench/tb_parallel_generalized.sv')
        for k,e,m in [(1,1,1),(3,1,4),(3,3,2),(3,4,3),(10,16,4),
                      (10,20,11),(5,19,10),(1,1,11),(4,17,5)]:
            with self.subTest(k=k,e=e,m=m):
                out=OUT/f'k{k}_e{e}_m{m}';out.mkdir(parents=True,exist_ok=True)
                manifest={'k':k,'e':e,'m':m,'scope':'independent memory/iteration/square RTL blocks; no Main IP integration',
                    'sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
                (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
                top='tb_parallel_generalized';binary=out/'parallel.vvp'
                command=['iverilog','-g2012','-I'+str(ROOT/'hardware_bram/src'),'-s',top,
                    f'-P{top}.K={k}',f'-P{top}.E={e}',f'-P{top}.M={m}',
                    '-o',str(binary),*(str(p) for p in sources if p.suffix!='.vh')]
                with (out/'compile.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
                with (out/'simulation.log').open('w') as log:
                    subprocess.run(['vvp',str(binary)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
                summary=[line for line in (out/'simulation.log').read_text().splitlines() if line.startswith('SUMMARY')]
                self.assertEqual(len(summary),1);self.assertIn('errors=0',summary[0])
                (out/'result.json').write_text(json.dumps(manifest|{'summary':summary[0]},indent=2)+'\n')
                print(summary[0],flush=True)

if __name__=='__main__':unittest.main()
