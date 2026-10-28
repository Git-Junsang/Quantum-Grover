#!/usr/bin/env python3
"""Compare this SoC transcript with this source's Verilator console replay.

The historical checker also compares old M2 measurements. This check uses the
current reference CSV for all HIT/STAT fields, command terminators and ENUM.
"""
from pathlib import Path
import json
import re
import sys

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
sys.path.insert(0, str(ROOT / "software/host_fpga_develop"))
sys.path.insert(0, str(ROOT / "hardware_bram/sim"))
import soc_console_check as checker

reference = {row["step"]: row for row in checker.csv_rows(OUT / "console_reference.csv")}
board = checker.bbht_cli.Board(checker.bbht_cli.ReplayTransport(OUT / "soc_transcript.txt"))
checks, runs, loaded, burst, current = 0, [], False, None, None


def equal(label, got, expected):
    global checks
    assert got == expected, f"{label}: got {got!r}, expected {expected!r}"
    checks += 1


for command in checker.script_lines():
    lines = board.cmd(command)
    head = command.upper().split()[0]
    term = checker.terminator(lines)
    expect_error = ((head == "RUN" and not loaded) or
                    (head == "SET" and re.search(r"MODE=(?!(LT|GT|EQ|RANGE)\b)", command.upper())))
    equal(command + " terminator", term.split()[0], "ERR" if expect_error else "OK")
    assert "REPLAY_" not in term
    if head == "LOAD":
        loaded = True
    if head == "SET":
        match = re.search(r"BURST=(\d+)", command.upper())
        if match:
            burst = int(match.group(1))
    if head == "RUN" and not expect_error:
        step = "run" + str(len(runs) + 1)
        current = reference[step]
        hit = checker.kv_of(lines, "HIT")
        equal(step + " burst", burst, int(current["burst"]))
        for (_, key), column in zip(checker.HIT_KEYS, ("idx", "trials", "l_bbht", "actual_iter", "cyc")):
            equal(step + " HIT " + key, hit.get(key), int(current[column]))
        runs.append(step)
    if head == "STAT" and current is not None:
        stat = checker.kv_of(lines, "STAT")
        for key in checker.STAT_KEYS:
            equal(runs[-1] + " STAT " + key, stat.get(key), int(current[key]))
    if head == "ENUM":
        found = [checker.bbht_cli.parse_kv_line(line)[1] for line in lines if line.startswith("FOUND")]
        indices = [entry["idx"] for entry in found]
        end = checker.kv_of(lines, "END")
        equal("ENUM order", indices, [int(item) for item in reference["enum"]["enum_idx"].split()])
        equal("ENUM cycles", end.get("cyc"), int(reference["enum"]["cyc"]))
        equal("ENUM count", end.get("count"), len(found))
        equal("ENUM found", end.get("found"), len(found))
        equal("ENUM unique", len(set(indices)), len(indices))

equal("run sequence", runs, [step for step in reference if step.startswith("run")])
assert "Errors: 0, Warnings: 0" in (OUT / "soc_qtsim.log").read_text()
result = {"checks": checks, "errors": 0, "runs": runs, "enum_indices": indices,
          "simulator_errors": 0, "simulator_warnings": 0}
(OUT / "soc_equivalence.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result))
