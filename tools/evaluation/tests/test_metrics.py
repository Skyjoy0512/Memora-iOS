import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('metrics', Path(__file__).parents[1] / 'quality_metrics.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)

class MetricsTests(unittest.TestCase):
    def test_app_diagnostic_bridge_preserves_unknowns_and_parallel_time(self):
        raw = {'requestCount': 2, 'measurementsIncomplete': False, 'requests': [
            {'inputTokens': 100, 'outputTokens': 20, 'cachedInputTokens': 80, 'outcome': 'completed', 'totalSeconds': 30},
            {'inputTokens': 50, 'outputTokens': 10, 'cachedInputTokens': 40, 'outcome': 'completed', 'totalSeconds': 30}]}
        result = M.summary_measurements(raw, 'openAI')
        self.assertEqual(result['inputTokens'], 150)
        self.assertEqual(result['cacheHitRate'], .8)
        self.assertIsNone(result['reasoningTokens'])
        self.assertNotIn('summarySeconds', result)
        self.assertNotIn('tokensPerSecond', result)
        raw['measurementsIncomplete'] = True
        self.assertIsNone(M.summary_measurements(raw, 'openAI')['inputTokens'])
        self.assertEqual(M.summary_measurements(raw, 'openAI')['requests'], 2)
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
        one = dict.fromkeys(('sourceSHA256', 'instructionSHA256', 'endpointSHA256', 'provider', 'model', 'reasoning',
                             'outputBudget', 'datasetRevision', 'promptVersion', 'measurementKind'), 'same')
        self.assertTrue(M.comparable(one, one))
        self.assertFalse(M.comparable(one, dict(one, model='different')))
