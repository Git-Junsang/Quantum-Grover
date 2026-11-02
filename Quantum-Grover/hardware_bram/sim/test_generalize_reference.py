"""Check the faster verifier against the unpruned independent reference DP."""
import random
import unittest

import generalize


class ExactReferenceTests(unittest.TestCase):
    def test_pruning_preserves_cost_action_and_ties(self):
        random_source=random.Random(291029)
        for capacity in range(1,11):
            for horizon in range(1,11):
                for _ in range(8):
                    held=tuple(sorted(random_source.sample(range(7),
                        random_source.randrange(min(capacity,7)+1))))
                    window=tuple(random_source.randrange(7) for _ in range(horizon+1))
                    mode=random_source.choice([5,6])
                    with self.subTest(capacity=capacity,horizon=horizon,held=held,window=window,mode=mode):
                        self.assertEqual(generalize.oracle(held,window,capacity,mode),
                            generalize.oracle_exhaustive(held,window,capacity,mode))


if __name__=='__main__':
    unittest.main()
