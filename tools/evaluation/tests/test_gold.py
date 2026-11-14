import importlib.util
from pathlib import Path
import unittest
SPEC = importlib.util.spec_from_file_location('gold', Path(__file__).parents[1] / 'gold_fixtures.py')
GOLD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GOLD)

class GoldFixtureTests(unittest.TestCase):
    def test_25_scenarios_include_long_withdrawal_and_sources(self):
        cases = GOLD.load()
        self.assertEqual(len(cases), 25)
        self.assertEqual([c['minutes'] for c in cases if 'minutes' in c], [5, 15, 30, 60, 120, 190])
        long = next(c for c in cases if c['id'] == 'duration-190')
        self.assertGreater(sum(len(s['text']) for s in long['transcript']), 50000)
        self.assertIn('撤回', long['transcript'][-1]['text'])
        for case in cases:
            self.assertEqual(len({s['id'] for s in case['transcript']}), len(case['transcript']))
            self.assertTrue(all('sourceSegmentID' in f for f in case['gold']))
