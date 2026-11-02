#!/usr/bin/env python3
"""Collect cache-only measurements from completed existing OOC runs.

The watcher never launches Vivado or changes RTL. It reads reports at a fixed
interval and stops after the requested larger-capacity cases are collected,
or when their existing synthesis runner has stopped without producing them.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import shutil
import time
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo


TARGETS = ("k5h7e4m4", "k6h8e4m4", "k7h8e4m4")
REGIONS = ("candidate_cache", "memo")
KINDS = ("ramb36", "ramb18", "distributed_ram_primitive",
         "named_flip_flop", "named_logic_lut", "named_shift_register")


def now() -> datetime:
    return datetime.now(ZoneInfo("Asia/Seoul"))


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def synthesis_runner_exists(source: Path) -> bool:
    for process in Path("/proc").iterdir():
        if not process.name.isdigit() or int(process.name) == os.getpid():
            continue
        try:
            arguments = [v.decode(errors="replace") for v in
                         (process / "cmdline").read_bytes().split(b"\0") if v]
            if (arguments and Path(arguments[0]).name.startswith("python")
                    and any(v.endswith("engine_sweep.py") for v in arguments[1:3])
                    and "--out" in arguments
                    and Path(arguments[arguments.index("--out") + 1]).resolve() == source.resolve()):
                return True
        except (OSError, IndexError):
            continue
    return False


def collect(source: Path, destination: Path) -> dict:
    destination.mkdir(parents=True, exist_ok=True)
    measurements = []
    unattributed = []
    for directory in sorted((source / "synth").glob("k*h*e*m*")):
        reports = directory / "policy_cache_memory.csv"
        if not reports.exists() or not (directory / "resource.json").exists():
            continue
        records = list(csv.DictReader(reports.open()))
        candidate = [r for r in records if r["region"] == "candidate_cache"]
        if not candidate:
            unattributed.append(directory.name)
            continue
        manifest = json.loads((directory / "manifest.json").read_text())
        config = manifest["config"]
        counts = Counter((r["region"], r["primitive_kind"]) for r in records)
        k, h = config["k"], config["h"]
        width = k + h + 1 + max(4, k).bit_length() + 11
        entries = (h + 1) * sum(math.comb(k + h, i) for i in range(k))
        row = {"configuration": directory.name, "k": k, "h": h,
               "e": config["e"], "m": config["m"],
               "logical_candidate_kib": entries * width / 8192,
               "policy_sha256": manifest["sha256"]["hardware_bram/src/grover_policy_parameterized.sv"]}
        for region in REGIONS:
            for kind in KINDS:
                row[f"{region}_{kind}"] = counts[region, kind]
        # These are allocated block capacities, not payload bit counts. LUTRAM
        # capacity cannot be inferred by treating every RAM primitive as a LUT.
        row["candidate_allocated_block_kib"] = (
            row["candidate_cache_ramb36"] * 4.5 + row["candidate_cache_ramb18"] * 2.25)
        measurements.append(row)
        output = destination / directory.name
        output.mkdir(exist_ok=True)
        hashes = {}
        for name in ("manifest.json", "resource.json", "util_hier.rpt",
                     "policy_cache_memory.csv", "policy_cache_audit_status.txt", "ram_utilization.rpt"):
            path = directory / name
            if path.exists():
                shutil.copy2(path, output / name)
                hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        write_json(output / "origin.json", {"source": str(directory), "sha256": hashes})
    if measurements:
        with (destination / "measured_cache.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(measurements[0]))
            writer.writeheader()
            writer.writerows(measurements)
    measured_names = {r["configuration"] for r in measurements}
    return {"checked_at": now().isoformat(), "source": str(source),
            "targets": list(TARGETS), "measured": sorted(measured_names),
            "pending_targets": [name for name in TARGETS if name not in measured_names],
            "unattributed_cases": unattributed,
            "policy_revisions": sorted({r["policy_sha256"] for r in measurements}),
            "scope": "cache and memo primitive attribution only; no device fitting boundary",
            "note": "Compare K/H scaling only within the same policy source revision. Named control LUT/FF attribution is partial."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--interval-seconds", type=int, default=1800)
    args = parser.parse_args()
    if args.interval_seconds < 1800:
        parser.error("watch checks must be at least 30 minutes apart")
    args.out.mkdir(parents=True, exist_ok=True)
    if args.watch:
        # The setup turn has already inspected available reports. The first
        # subsequent inspection is thirty minutes after this process starts.
        while True:
            next_check = now() + timedelta(seconds=args.interval_seconds)
            write_json(args.out / "watcher.json", {
                "pid": os.getpid(), "status": "waiting", "next_check_at": next_check.isoformat(),
                "interval_seconds": args.interval_seconds, "targets": list(TARGETS)})
            time.sleep(args.interval_seconds)
            status = collect(args.source, args.out)
            status["synthesis_runner_active"] = synthesis_runner_exists(args.source)
            status["status"] = ("complete" if not status["pending_targets"] else
                                "waiting" if status["synthesis_runner_active"] else
                                "stopped_missing_results")
            write_json(args.out / "status.json", status)
            print(json.dumps(status, ensure_ascii=False), flush=True)
            if status["status"] != "waiting":
                write_json(args.out / "watcher.json", {
                    "pid": os.getpid(), "status": status["status"], "finished_at": now().isoformat(),
                    "interval_seconds": args.interval_seconds})
                return
    else:
        status = collect(args.source, args.out)
        status["status"] = "initial_audit"
        write_json(args.out / "status.json", status)
        print(json.dumps(status, ensure_ascii=False))


if __name__ == "__main__":
    main()
