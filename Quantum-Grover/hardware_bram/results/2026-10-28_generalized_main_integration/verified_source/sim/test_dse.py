#!/usr/bin/env python3
"""Boundary tests for numeric BUILD bandwidth and H7/H8 shadow lookahead."""
import copy
import json
import random
from pathlib import Path
import subprocess
import tempfile
import unittest

import dse
import kh_sweep as kh


class DesignSpaceTests(unittest.TestCase):
    def test_unsupported_parameters_fail_before_build(self):
        base=json.loads(Path(dse.__file__).with_name("dse_200t.json").read_text())
        for key, value in (("k",5),("h",9),("e",8),("build_rows",5)):
            config=copy.deepcopy(base)
            config["grid"][key]=[value]
            with self.assertRaises(ValueError): dse.config_cells(config)
        config=copy.deepcopy(base)
        config["grid"]["e"]=[2]
        with self.assertRaises(ValueError): dse.config_cells(config)

    def test_shadow_horizons_and_restart(self):
        rng=random.Random(27027)
        contexts=[(rng.getrandbits(32),rng.randrange(28),rng.choice([0,300,574,575]),
                   rng.choice([0,98,99,100])) for _ in range(80)]
        with tempfile.TemporaryDirectory(prefix="bbht_shadow_") as temp:
            directory=Path(temp)
            for count in (7,8,9,10,11):
                vectors=[]
                for state,round_idx,total,trial in contexts:
                    initial=(state,round_idx,total,trial)
                    draws=0
                    values=[]
                    while len(values)<count:
                        if trial>=100 or total+1>=576:
                            round_idx,total,trial=0,0,0
                        bound=kh.M_BOUNDS[round_idx]
                        candidate=state & ((1 << (bound-1).bit_length())-1)
                        state=kh.lfsr_step(kh.lfsr_step(kh.lfsr_step(kh.lfsr_step(kh.lfsr_step(kh.lfsr_step(kh.lfsr_step(state)))))))
                        draws+=1
                        if candidate<bound:
                            values.append(candidate)
                            round_idx=min(27,round_idx+1)
                            total+=candidate
                            trial+=1
                    packed=sum(v << (7*i) for i,v in enumerate(values))
                    vectors.append(f"{initial[0]:x} {initial[1]} {initial[2]} {initial[3]} {packed:x} {state:x} {round_idx} {total} {trial} {draws}")
                path=directory / "vectors.txt"
                path.write_text("\n".join(vectors)+"\n")
                binary=directory / "sim"
                subprocess.run(["iverilog","-g2012","-s","tb_shadow_horizon",
                                "-I",str(dse.ROOT / "hardware_bram/src"),
                                "-P",f"tb_shadow_horizon.FUTURE_COUNT={count}","-o",str(binary),
                                str(dse.ROOT / "hardware_bram/testbench/tb_shadow_horizon.sv"),
                                str(dse.ROOT / "hardware_bram/src/grover_policy.v")],check=True)
                subprocess.run(["vvp",str(binary),f"+VECTORS={path}"],check=True)

    def test_born_build_bandwidth_equivalence(self):
        with tempfile.TemporaryDirectory(prefix="bbht_born_") as temp:
            binary=Path(temp) / "sim"
            subprocess.run(["iverilog","-g2012","-s","tb_measure_build_rows",
                            "-I",str(dse.ROOT / "hardware_bram/src"),"-o",str(binary),
                            str(dse.ROOT / "hardware_bram/testbench/tb_measure_build_rows.sv"),
                            *(str(dse.ROOT / "hardware_bram/src" / (name+".v"))
                              for name in ("grover_measurement","grover_arithmetic","grover_memories"))],check=True)
            subprocess.run(["vvp",str(binary)],check=True)


if __name__=="__main__": unittest.main()
