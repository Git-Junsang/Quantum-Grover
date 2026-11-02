#!/usr/bin/env python3
"""Link read-only observers to the already verified Verilator model archive."""
from pathlib import Path
import hashlib
import json
import os
import subprocess

OUT=Path(__file__).resolve().parent
fingerprint=hashlib.sha256((str(OUT)+'k3h3_e4_b3_p6').encode()).hexdigest()[:16]
BUILD=Path('/tmp/bbht_dse_'+fingerprint)
OBJ=BUILD/'obj'
commands=[]
for name,source,csv_name,log_name in (
    ('profile',OUT/'tb_profile.cpp','bench_profile.csv','profile.log'),
    ('console',OUT/'source/tb_console_seq.cpp','console_reference.csv','console_reference.log')):
    binary=BUILD/('observer_'+name)
    command=['g++','-O2','-std=c++17','-DBBHT_HOST_TEST','-DBBHT_NO_PRINTF','-DBBHT_TIMEOUT=200000000',
        '-I'+str(OBJ),'-I'+str(BUILD/'src'),'-I/usr/share/verilator/include',
        '-I/usr/share/verilator/include/vltstd',str(source),str(OBJ/'Vbbht_rvx_wrapper__ALL.a'),
        str(OBJ/'verilated.o'),str(OBJ/'verilated_threads.o'),str(BUILD/'driver.o'),
        '-pthread','-latomic','-o',str(binary)]
    commands.append(command)
    with (OUT/(name+'_build.log')).open('w') as log:
        subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
    with (OUT/csv_name).open('w') as stdout,(OUT/log_name).open('w') as stderr:
        subprocess.run([str(binary)],env=os.environ|{'WL_DIR':str(OUT/'workload'),'BENCH_LIMIT':'500'},
                       stdout=stdout,stderr=stderr,check=True)
(OUT/'observer_commands.json').write_text(json.dumps(commands,indent=2)+'\n')
