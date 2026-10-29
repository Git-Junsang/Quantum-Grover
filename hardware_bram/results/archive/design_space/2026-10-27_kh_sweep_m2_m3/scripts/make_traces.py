#!/usr/bin/env python3
"""Write exhaustive-policy reference traces for the standalone RTL harness."""
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])  # worktree hardware_bram/sim
import kh_sweep

out = Path(sys.argv[2])
cells = [(int(c[1]), int(c[3])) for c in sys.argv[3].split(",")]  # K3H3,...
workloads = kh_sweep.load_workloads(kh_sweep.DEFAULT_TRACE, kh_sweep.DEFAULT_ROSTER, 8, None)
for k, h in cells:
    metrics, rows = kh_sweep.replay_cell(workloads, k, h)
    kh_sweep.write_trace(out / f"trace_k{k}h{h}.txt", rows)
    print(f"K{k}H{h} decisions={metrics['decisions']} physical={metrics['physical_iterations']}", flush=True)
