import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import summary_report as R


class ReportTests(unittest.TestCase):
    def run_fixture(self, case_id='no-owner'):
        case = next(c for c in R.load() if c['id'] == case_id)
        # Synthetic annotations test the gate, never report a model score.
        annotation = {k: [f['id'] for f in case['gold'] if f['category'] == k]
                      for k in ('facts', 'decisions', 'actions')}
        annotation.update(reviewer='human', reviewID='unit-fixture-only', claims=[
            dict(goldID=f['id'], sourceSegmentID=f['sourceSegmentID'], quote=f['quote'],
                 speaker=f['speaker'], owner=f.get('owner'), due=f.get('due')) for f in case['gold']])
        run = dict.fromkeys(('instructionSHA256', 'provider', 'model', 'reasoning', 'outputBudget',
                             'datasetRevision', 'promptVersion'), 'synthetic-condition')
        run.update(caseID=case_id, runID='one', sourceSHA256=R.source_hash(case),
                   measurementKind='mock', annotation=annotation, summarySeconds=None, costUSD=None)
        return case, run

    def test_mock_unknown_metrics_cannot_pass(self):
        _, before = self.run_fixture()
        result = R.report([before], [dict(before, runID='two')])
        self.assertTrue(result['blocksAutomaticAdoption'])
        self.assertIn('not_real_provider_measurements', result['blockingReasons'])
        self.assertIn('missing_summarySeconds', result['blockingReasons'])
        self.assertIsNone(result['officialJMeetEvalScore'])
        self.assertEqual(result['apiRequests'], 0)

    def test_invented_owner_and_retracted_decision_are_critical(self):
        case, run = self.run_fixture()
        run['annotation']['claims'][0]['owner'] = '架空の社長'
        self.assertIn('invented_or_wrong_owner', R.evaluate(case, run)['criticalErrors'])
        case, run = self.run_fixture('retraction')
        run['annotation']['claims'][0].update(category='decisions', status='confirmed', content='11月20日に公開する')
        self.assertIn('withdrawn_decision_as_current', R.evaluate(case, run)['criticalErrors'])

    def test_conditions_and_review_are_required(self):
        _, before = self.run_fixture()
        after = copy.deepcopy(before)
        after.update(runID='two', model='different', sourceSHA256='different')
        after['annotation']['reviewer'] = 'judge-only'
        result = R.report([before], [after])
        self.assertIn('incomparable_conditions', result['blockingReasons'])
        self.assertIn('source_mismatch', result['blockingReasons'])
        self.assertIn('semantic_review_missing', result['blockingReasons'])
