import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('metrics', Path(__file__).parents[1] / 'quality_metrics.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)

class MetricsTests(unittest.TestCase):
    def test_critical_error_cannot_hide_in_average(self):
        result = M.quality({'facts': ['f1'], 'actions': ['a1']},
                           {'facts': ['f1'], 'actions': ['a1', 'invented'], 'reviewer': 'human'})
        self.assertFalse(result['passesCriticalGate'])
        self.assertAlmostEqual(result['actions']['precision'], .5)
        self.assertAlmostEqual(result['actions']['recall'], 1)

    def test_no_unknown_measurement_becomes_zero(self):
        result = M.performance([{'summarySeconds': 30}, {'summarySeconds': 120}, {'summarySeconds': None}])
        self.assertEqual(result['summarySeconds']['p50'], 30)
        self.assertEqual(result['summarySeconds']['p95'], 120)
        self.assertEqual(result['summarySeconds']['unknownSamples'], 1)
        self.assertIsNone(result['costUSD']['p50'])

    def test_incomparable_model_does_not_establish_speedup(self):
        self.assertFalse(M.comparable({}, {}))
        one = dict.fromkeys(('sourceSHA256', 'instructionSHA256', 'provider', 'model', 'reasoning',
                             'outputBudget', 'datasetRevision', 'promptVersion', 'measurementKind'), 'same')
        self.assertTrue(M.comparable(one, one))
        self.assertFalse(M.comparable(one, dict(one, model='different')))
