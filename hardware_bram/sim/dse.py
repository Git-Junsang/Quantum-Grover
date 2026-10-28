#!/usr/bin/env python3
"""Config-driven checkpoint RTL experiments: prepare/policy/sim/synth/route/report.

All cells consume one source snapshot and the same ordered Common500 prefix.
K/H/engine count/BUILD bandwidth and the FPGA part/clock live in JSON.  A run
directory refuses changed inputs; use a new directory for changed RTL/config.
No board programming or 100T resource restriction is applied by this runner.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import kh_sweep as kh

ROOT = Path(__file__).resolve().parents[2]
SV_CORE = {"grover_parallel", "grover_policy_parameterized"}
CORE = "bbht_grover_main_ip grover_arithmetic grover_bbht grover_checkpoint grover_iteration grover_loader grover_measurement grover_memories grover_policy grover_status grover_parallel grover_policy_parameterized".split()
COMM = "bbht_rvx_wrapper bbht_grover_mmio bbht_ahb_loader".split()
TEMPLATE = ROOT / "hardware_bram/configurations/capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit/src/bbht_grover_core_adapter.v"
TCL = ROOT / "hardware_bram/synth/dse_ooc.tcl"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def config_cells(config):
    if config.get("schema") != 1:
        raise ValueError("config schema must be 1")
    target = config["target"]
    if not re.fullmatch(r"xc7a(?:100|200)t[a-z0-9]+-[123]", target["part"]):
        raise ValueError("target.part must be a complete Artix-7 100T/200T part")
    if not math.isfinite(float(target["clock_ns"])) or float(target["clock_ns"]) <= 0:
        raise ValueError("clock_ns must be finite and positive")
    if type(config.get("workload_limit")) is not int or not 1 <= config["workload_limit"] <= 500:
        raise ValueError("workload_limit must be 1..500")
    if type(config.get("hier_select")) is not bool:
        raise ValueError("hier_select must be boolean")
    allowed = {"k": {3, 4}, "h": set(range(1, 9)), "e": {1, 2, 4},
               "build_rows": {1, 2, 3, 4}, "prune": set(range(7))}
    grid = config["grid"]
    if set(grid) != set(allowed):
        raise ValueError(f"grid must contain {list(allowed)}")
    for key, domain in allowed.items():
        values = grid[key]
        if not isinstance(values, list) or not values or any(type(v) is not int or v not in domain for v in values):
            raise ValueError(f"unsupported {key}: {values}; RTL supports {sorted(domain)}")
    cells = []
    for values in itertools.product(*(sorted(set(grid[k])) for k in allowed)):
        cell = dict(zip(allowed, values))
        if cell["build_rows"] > 1 and cell["e"] != 4:
            raise ValueError("parallel measurement BUILD currently requires E4 memory ports")
        cell["id"] = "k{k}h{h}_e{e}_b{build_rows}_p{prune}".format(**cell)
        cells.append(cell)
    return cells


def run(command, log, *, env=None, cwd=None):
    print(f"  {log.parent.name}: {Path(str(command[0])).name} -> {log.name}", flush=True)
    with log.open("w") as handle:
        result = subprocess.run([str(v) for v in command], cwd=cwd, env=env,
                                stdout=handle, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {log}")


def prepare(out, config, cells):
    sources = [ROOT / "hardware_bram/src" / (name + (".sv" if name in SV_CORE else ".v")) for name in CORE + COMM]
    sources += [ROOT / "hardware_bram/src/grover_param.vh",
                ROOT / "spec/generated/bbht_grover_csr.vh",
                ROOT / "spec/generated/bbht_grover_regs.h",
                ROOT / "hardware_bram/firmware/bbht_grover_driver.c",
                ROOT / "hardware_bram/firmware/bbht_grover_driver.h",
                ROOT / "hardware_bram/testbench/tb_bench500.cpp"]
    sources += [kh.TB]
    extras = [TEMPLATE, TCL, Path(__file__).resolve(), Path(kh.__file__).resolve(),
              kh.DEFAULT_TRACE, kh.DEFAULT_ROSTER,
              ROOT / "software/reference_model_develop/tb_stimulus/dump_bench_workload.py"]
    hashes = {str(p.relative_to(ROOT)): digest(p) for p in sources + extras}
    manifest = {"config": config, "cells": cells, "sha256": hashes,
                "scope": "accelerator OOC; RTL cycles; board measurements not included"}
    path = out / "manifest.json"
    if path.exists():
        if json.loads(path.read_text()) != manifest:
            raise ValueError("run inputs changed; select a new --out directory")
        for source in sources + [TCL]:
            snapshot = out / "source" / source.name
            if not snapshot.exists() or digest(snapshot) != digest(source):
                raise ValueError(f"source snapshot changed: {snapshot}")
        for cell in cells:
            directory = out / cell["id"]
            generated = json.loads((directory / "generated_sha256.json").read_text())
            if any(digest(directory / name) != sha for name, sha in generated.items()):
                raise ValueError(f"generated cell inputs changed: {directory}")
        return
    out.mkdir(parents=True, exist_ok=True)
    snapshot = out / "source"
    snapshot.mkdir(exist_ok=True)
    for source in sources:
        shutil.copy2(source, snapshot / source.name)
    shutil.copy2(TCL, snapshot / TCL.name)
    for cell in cells:
        directory = out / cell["id"]
        directory.mkdir(exist_ok=True)
        adapter = TEMPLATE.read_text()
        parameters = {"CHECKPOINT_CAPACITY": cell["k"], "LOOKAHEAD_SHOTS": cell["h"],
                      "NUMBER_OF_PES": cell["e"], "POLICY_SEARCH_MODE": cell["prune"],
                      "USE_TWO_LEVEL_SELECT": int(config["hier_select"])}
        for key, value in parameters.items():
            adapter, count = re.subn(rf"(parameter integer {key}\s*=\s*)\d+", rf"\g<1>{value}", adapter)
            if count != 1:
                raise ValueError(f"adapter template parameter missing: {key}")
        adapter, count = re.subn(r"(parameter integer BUILD_ROWS_PER_CYCLE\s*=\s*)`GP_BUILD_ROWS_PER_CYCLE_DEFAULT",
                                 rf"\g<1>{cell['build_rows']}", adapter)
        if count != 1:
            raise ValueError("adapter template parameter missing: BUILD_ROWS_PER_CYCLE")
        # The template's old configuration prose is not the generated config.
        adapter = "// Generated from manifest.json; parameter defaults below are authoritative.\n" + adapter[adapter.index("`timescale"):]
        (directory / "adapter.v").write_text(adapter)
        save(directory / "parameters.json", parameters | {"BUILD_ROWS_PER_CYCLE": cell["build_rows"]})
        save(directory / "generated_sha256.json", {name: digest(directory / name)
             for name in ("adapter.v", "parameters.json")})
    save(path, manifest)


def policy(out, cell, limit):
    directory = out / cell["id"]
    if (directory / "policy.json").exists():
        return
    workloads = kh.load_workloads(kh.DEFAULT_TRACE, kh.DEFAULT_ROSTER, 8, limit)
    _, rows = kh.replay_cell(workloads, cell["k"], cell["h"])
    trace = directory / "policy_trace.txt"
    kh.write_trace(trace, rows)
    iterations=[]
    for reset, window, source, _ in rows:
        if reset: iterations.append(0)
        iterations[-1] += window[0]-source
    save(directory / "reference_iterations.json", iterations)
    metrics = kh.run_rtl_cell(directory, cell["k"], cell["h"], trace, cell["prune"],
                             out / "source/grover_policy.v", out / "source",
                             out / "source/tb_policy_kh_sweep.sv")
    save(directory / "policy.json", metrics)


def validate_bench(path, limit, expected_iterations=None):
    if "# DONE errors=0" not in path.read_text():
        raise ValueError(f"unfinished simulation: {path}")
    with path.open() as handle:
        rows = list(csv.DictReader(line for line in handle if not line.startswith("#")))
    if len(rows) != limit * 2:
        raise ValueError(f"expected {limit*2} rows in {path}, found {len(rows)}")
    with kh.DEFAULT_TRACE.open() as handle:
        golden = [json.loads(line) for line in handle if line.strip()][:limit]
    checkpoint = []
    for index, item in enumerate(golden):
        normal, ckpt = rows[2*index:2*index+2]
        attempts = item["attempts"]
        expected = {"m": item["target_count"], "seed_idx": item["seed_index"],
                    "trial": len(attempts), "l_bbht": sum(a[0] for a in attempts),
                    "result_index": attempts[-1][4] if attempts[-1][5] else 0xFFFFFFFF}
        if normal["mode"] != "normal" or ckpt["mode"] != "k4":
            raise ValueError("unexpected workload order/mode")
        for row in (normal, ckpt):
            if any(int(row[k]) != v for k, v in expected.items()) or int(row["mismatch"]) != 0:
                raise ValueError(f"golden trajectory mismatch at workload {index}: {path}")
        if int(normal["iter"]) != expected["l_bbht"] or int(ckpt["iter"]) > int(normal["iter"]):
            raise ValueError(f"invalid physical work at workload {index}: {path}")
        if expected_iterations is not None and int(ckpt["iter"]) != expected_iterations[index]:
            raise ValueError(f"policy horizon/physical work mismatch at workload {index}: {path}")
        checkpoint.append(ckpt)
    return {"validated_workloads": limit, **{field: sum(int(r[field]) for r in checkpoint)
            for field in ("cycles", "iter", "policy_cycles", "policy_stall", "policy_actions")}}


def simulate(out, cell, config):
    directory = out / cell["id"]
    if not (directory / "policy.json").exists():
        policy(out, cell, config["workload_limit"])
    if (directory / "sim.json").exists():
        return
    workload = out / "workload"
    if not (workload / "seeds.txt").exists():
        run([sys.executable, ROOT / "software/reference_model_develop/tb_stimulus/dump_bench_workload.py",
             "--seeds", 100, "--out", workload], out / "workload.log")
        save(out / "workload_sha256.json", {p.name: digest(p) for p in workload.iterdir() if p.is_file()})
    recorded = json.loads((out / "workload_sha256.json").read_text())
    if any(digest(workload / name) != sha for name, sha in recorded.items()):
        raise ValueError("workload files changed since generation")
    fingerprint = hashlib.sha256((str(out) + cell["id"]).encode()).hexdigest()[:16]
    build = Path("/tmp") / ("bbht_dse_" + fingerprint)
    src = build / "src"
    src.mkdir(parents=True, exist_ok=True)
    for p in (out / "source").iterdir():
        shutil.copy2(p, src / p.name)
    shutil.copy2(directory / "adapter.v", src / "adapter.v")
    defines = ["-DBBHT_HOST_TEST", "-DBBHT_NO_PRINTF", "-DBBHT_TIMEOUT=200000000"]
    run(["gcc", "-c", "-O2", *defines, "-I", src, src / "bbht_grover_driver.c",
         "-o", build / "driver.o"], directory / "driver_build.log")
    run(["verilator", "--cc", "--exe", "--build", "-j", "2", "-Wno-fatal", "-Wno-DECLFILENAME",
         "--Mdir", build / "obj", "-CFLAGS", " ".join(defines + [f"-I{src}", "-O2"]),
         "-LDFLAGS", str(build / "driver.o"), f"-I{src}",
         *(src / (name + (".sv" if name in SV_CORE else ".v")) for name in COMM + CORE), src / "adapter.v",
         "--top-module", "bbht_rvx_wrapper", src / "tb_bench500.cpp", "-o", "bench"],
        directory / "sim_build.log", cwd=build)
    env = os.environ | {"WL_DIR": str(workload), "BENCH_LIMIT": str(config["workload_limit"])}
    # Keep stderr out of CSV: workload progress belongs to a separate log.
    with (directory / "bench.csv").open("w") as stdout, (directory / "sim.log").open("w") as stderr:
        subprocess.run([str(build / "obj/bench")], env=env, stdout=stdout, stderr=stderr, check=True)
    save(directory / "sim.json", validate_bench(directory / "bench.csv", config["workload_limit"],
         json.loads((directory / "reference_iterations.json").read_text())))


def vivado(out, cell, config, stage, executable):
    directory = out / cell["id"]
    destination = directory / stage
    if (destination / "done.json").exists():
        return
    if not (directory / "sim.json").exists() or not (directory / "policy.json").exists():
        raise ValueError(f"run sim before {stage}: {cell['id']}")
    if stage == "route" and not (directory / "synth/synth.dcp").exists():
        raise ValueError("run synth before route")
    destination.mkdir(exist_ok=True)
    env = os.environ | {"DSE_SRC": str(out / "source"), "DSE_CELL": str(directory),
                        "DSE_OUT": str(destination), "DSE_STAGE": stage,
                        "DSE_PART": config["target"]["part"],
                        "DSE_CLOCK_NS": str(config["target"]["clock_ns"])}
    run([executable, "-mode", "batch", "-source", out / "source/dse_ooc.tcl",
         "-log", destination / "vivado.log", "-journal", destination / "vivado.jou"],
        destination / "run.log", env=env, cwd=destination)
    save(destination / "done.json", {"scope": "accelerator OOC", "stage": stage})


def report(out, config, cells):
    rows = []
    for cell in cells:
        directory = out / cell["id"]
        row = dict(cell)
        for phase in ("policy", "sim"):
            p = directory / f"{phase}.json"
            if p.exists(): row.update(json.loads(p.read_text()))
        if "cycles" in row:
            row["nominal_time_us"] = row["cycles"] * config["target"]["clock_ns"] / 1000
        slack = directory / "route/slack.csv"
        if (directory / "route/done.json").exists() and slack.exists():
            with slack.open() as handle:
                row.update({k: float(v) for k, v in next(csv.DictReader(handle)).items()})
            row["ooc_timing_pass"] = row["wns_ns"] >= 0 and row["whs_ns"] >= 0
        for stage in ("route", "synth"):
            p = directory / stage / "util.rpt"
            if (directory / stage / "done.json").exists() and p.exists():
                sys.path.insert(0, str(ROOT / "hardware_bram/synth"))
                from parse_resource import parse_flat
                resources = parse_flat(p.read_text())
                if resources is None: raise ValueError(f"cannot parse utilization: {p}")
                row.update(dict(zip(("lut", "ff", "bram_tile", "dsp"), resources)))
                row["resource_stage"] = stage
                break
        rows.append(row)
    kh.write_csv(out / "summary.csv", rows)
    os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-bbht-dse")
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    groups = sorted({(c["e"], c["build_rows"], c["prune"]) for c in cells})
    for e, b, p in groups:
        selected = [r for r in rows if (r["e"], r["build_rows"], r["prune"]) == (e,b,p)]
        ks, hs = sorted({r["k"] for r in selected}), sorted({r["h"] for r in selected})
        fig, axes = plt.subplots(1,3,figsize=(14,4),constrained_layout=True)
        for ax, field, title in zip(axes, ("cycles","policy_stall","wns_ns"),
                                   ("Integrated RTL cycles","Exposed policy stall (cycles)","OOC routed WNS (ns)")):
            values = np.full((len(ks),len(hs)), np.nan)
            for r in selected:
                if field in r: values[ks.index(r["k"]),hs.index(r["h"])]=r[field]
            im=ax.imshow(np.ma.masked_invalid(values),origin="lower",aspect="auto",cmap="YlOrRd")
            ax.set_xticks(range(len(hs)),hs); ax.set_yticks(range(len(ks)),ks)
            ax.set_xlabel("H"); ax.set_ylabel("K"); ax.set_title(title)
            for y in range(len(ks)):
                for x in range(len(hs)):
                    v=values[y,x]
                    ax.text(x,y,"unmeasured" if math.isnan(v) else f"{v:,.3f}" if field=="wns_ns" else f"{v:,.0f}",ha="center",va="center",fontsize=8)
            if np.isfinite(values).any(): fig.colorbar(im,ax=ax,shrink=.8)
        fig.suptitle(f"E{e} / BUILD {b} rows/clock / prune {p}; Common500 prefix {config['workload_limit']}; {config['target']['part']}")
        fig.savefig(out / f"heatmap_e{e}_b{b}_p{p}.png",dpi=160)
        plt.close(fig)
    print(f"Results: {out / 'summary.csv'}",flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config",type=Path,default=Path(__file__).with_name("dse_200t.json"))
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--stages",default="prepare",help="comma-separated prepare,policy,sim,synth,route,report")
    parser.add_argument("--vivado",default=os.environ.get("VIVADO_BIN","vivado"))
    args=parser.parse_args()
    config=json.loads(args.config.read_text())
    cells=config_cells(config)
    stages=args.stages.split(",")
    if any(s not in ("prepare","policy","sim","synth","route","report") for s in stages):
        parser.error("unknown stage")
    out=args.out.resolve()
    prepare(out,config,cells)
    print(f"{len(cells)} cells, {config['target']}, workloads={config['workload_limit']}",flush=True)
    for stage in stages:
        if stage=="prepare": continue
        if stage=="report": report(out,config,cells); continue
        for cell in cells:
            print(f"{stage}: {cell['id']}",flush=True)
            if stage=="policy": policy(out,cell,config["workload_limit"])
            elif stage=="sim": simulate(out,cell,config)
            else: vivado(out,cell,config,stage,args.vivado)
    return 0


if __name__=="__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}",file=sys.stderr)
        raise SystemExit(1)
