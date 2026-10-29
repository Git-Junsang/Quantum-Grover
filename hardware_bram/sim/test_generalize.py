#!/usr/bin/env python3
"""Directed width, search, hash collision, and production-backend checks."""
from pathlib import Path
import json
import tempfile
import unittest
import generalize

# Keep each invocation separate from the immutable evidence in results/archive.
# A fresh directory also prevents a rerun with newer RTL from reusing an old
# manifest or overwriting the source snapshot of the historical experiment.
OUT=Path(tempfile.mkdtemp(prefix='bbht_policy_unit_'))

class ParameterizedPolicyTests(unittest.TestCase):
    def test_exact_backends(self):
        # Selected boundary tests, not a performance sweep over all 100 cells.
        for k,h,mode,lanes,force in [(1,10,6,4,True),(2,4,5,1,True),
            (3,3,6,4,True),(3,3,6,4,False),(3,9,6,4,True),
            (4,8,5,2,True),(4,10,6,4,True),(5,3,6,4,True),(10,10,6,4,True)]:
            data={'schema':2,'k':k,'h':h,'e':16,'m':4,'policy_mode':mode,
                'scan_lanes':lanes,'force_generic':force}
            with self.subTest(k=k,h=h,mode=mode,lanes=lanes,force=force):
                generalize.run(data,OUT/f'k{k}h{h}_p{mode}_l{lanes}_{"generic" if force else "production"}',48)

if __name__=='__main__':unittest.main()
