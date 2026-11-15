import copy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.error
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import model_runner as runner


def manifest():
    source = [{'id': 's1', 'text': '公開を撤回。予算150万円、担当・期限は保留。'}]
    body = {'model': 'evaluation-only-model', 'messages': [{'role': 'user', 'content': source[0]['text']}],
            'max_tokens': 500, 'stream': False}
    return {'schemaVersion': 1, 'limits': {'requests': 2, 'tokens': 10000, 'seconds': 10, 'costUSD': '0.01'},
            'requests': [{'runID': 'run-1', 'caseID': 'synthetic', 'variant': 'single-pass',
                'provider': 'compatible', 'protocol': 'chat-completions', 'endpoint': 'https://evaluation.invalid/v1/chat/completions',
                'source': source, 'sourceSHA256': runner.digest(json.dumps(source, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()),
                'body': body, 'instructionSHA256': runner.digest(json.dumps(body, ensure_ascii=False, separators=(',', ':')).encode()),
                'appCommit': 'fixture', 'promptVersion': 'v1', 'datasetRevision': 'v1', 'cacheState': 'cold', 'concurrency': 1,
                'outputLimitField': 'max_tokens', 'billingContract': {'reviewID': 'fixture-only', 'outputIncludesReasoning': True,
                    'contextTokens': 10000, 'framingUpperTokens': 2000, 'maximumInputUSDPerMillion': '0.1', 'maximumOutputUSDPerMillion': '0.2'}}]}


def grant(value):
    return {'expiresAt': (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat(),
            'manifestSHA256': runner.digest(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()),
            'sourceTransmissionApproved': True, 'credentialEnvironment': 'MEMORA_EVALUATION_API_KEY',
            'endpoints': [value['requests'][0]['endpoint']],
            'spendGuard': {'kind': 'billing-proxy', 'receiptID': 'offline-fixture-only', 'hardCapUSD': '0.01'}}


class ModelRunnerTests(unittest.TestCase):
    def test_dry_run_no_network_or_credentials(self):
        with patch.dict('os.environ', {'MEMORA_EVALUATION_API_KEY': 'must-not-read'}), patch('urllib.request.build_opener', side_effect=AssertionError('network')):
            result = runner.validate(manifest())
        self.assertEqual(result['apiRequests'], 0)
        self.assertEqual(result['measurementKind'], 'plan-only')

    def test_all_upper_bounds(self):
        for field, value in [('requests', 0), ('tokens', 1), ('costUSD', '0.0000001'), ('seconds', True), ('costUSD', 'NaN')]:
            item = manifest()
            item['limits'][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                runner.validate(item)
        for mutate in (
            lambda r: r.update(sourceSHA256='forged'),
            lambda r: r.update(instructionSHA256='forged'),
            lambda r: r.update(endpoint='https://user:secret@host.test/api'),
            lambda r: r.update(endpoint='http://host.test/api'),
            lambda r: r['body'].update(n=5),
            lambda r: r['body'].update(max_completion_tokens=50000),
            lambda r: r['body'].update(tools=[{'type': 'web_search'}]),
            lambda r: r['billingContract'].update(outputIncludesReasoning=False),
            lambda r: r['billingContract'].update(maximumInputUSDPerMillion=None),
            lambda r: r['billingContract'].update(contextTokens=100),
        ):
            item = manifest(); mutate(item['requests'][0])
            with self.assertRaises(ValueError): runner.validate(item)

    def test_grant_and_daily_key_are_not_interchangeable(self):
        item = manifest()
        for mutate in (
            lambda g: g.update(sourceTransmissionApproved=False),
            lambda g: g.update(manifestSHA256='wrong'),
            lambda g: g.update(credentialEnvironment='DEEPSEEK_API_KEY'),
            lambda g: g.update(expiresAt='2000-01-01T00:00:00Z'),
            lambda g: g['spendGuard'].update(kind='client-estimate'),
            lambda g: g['spendGuard'].update(hardCapUSD='1'),
            lambda g: g.update(endpoints=['https://other.invalid']),
        ):
            permission = grant(item); mutate(permission)
            with self.assertRaises(ValueError): runner.authorize(item, permission)

    def test_result_unknowns_and_no_automatic_adoption(self):
        item = manifest()
        response = {'choices': [{'finish_reason': 'stop', 'message': {'content': '予算150万円。公開は撤回。'}}],
                    'usage': {'prompt_tokens': 50, 'completion_tokens': 20}}
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'run'
            result = runner.execute(item, grant(item), target, sender=lambda *a: response, credential=lambda: 'synthetic')
            self.assertEqual(result[0]['status'], 'completed')
            self.assertEqual(result[0]['measurementKind'], 'raw-provider-request')
            self.assertIsNone(result[0]['summarySeconds'])
            self.assertIsNone(result[0]['costUSD'])
            self.assertIsNone(result[0]['peakMemory'])
            self.assertFalse(json.loads((target / 'result.json').read_text())['automaticAdoption'])
            with self.assertRaises(FileExistsError):
                runner.execute(item, grant(item), target, credential=lambda: self.fail('credential read before overwrite refusal'))

    def test_429_and_unknown_failure_never_retry(self):
        item = manifest()
        second = copy.deepcopy(item['requests'][0]); second['runID'] = 'run-2'
        item['requests'].append(second)
        for status in (429, 401, 503):
            calls = []
            def fail(*args):
                calls.append(1)
                raise urllib.error.HTTPError('https://private.invalid/secret', status, 'sensitive', {'Retry-After': '120'}, None)
            with tempfile.TemporaryDirectory() as directory:
                rows = runner.execute(item, grant(item), Path(directory) / 'run', sender=fail, credential=lambda: 'secret')
                self.assertEqual(len(calls), 1)
                self.assertEqual(rows[0]['httpStatus'], status)
                self.assertNotIn('secret', json.dumps(rows))

    def test_truncated_refusal_or_tool_response_fail(self):
        for choice in ({'finish_reason': 'length', 'message': {'content': 'partial'}},
                       {'finish_reason': 'stop', 'message': {'content': 'text', 'tool_calls': [{}]}},
                       {'finish_reason': 'stop', 'message': {'content': ''}},
                       {'finish_reason': 'stop', 'message': {'refusal': 'no', 'content': 'no'}}):
            item = manifest()
            with tempfile.TemporaryDirectory() as directory:
                rows = runner.execute(item, grant(item), Path(directory) / 'run', sender=lambda *a: {'choices': [choice]}, credential=lambda: 'synthetic')
                self.assertEqual(rows[0]['status'], 'failed')

    def test_elapsed_deadline_marks_unknown_billing_failure(self):
        item = manifest()
        readings = iter([0, 0, 0, 11, 11])
        with tempfile.TemporaryDirectory() as directory:
            rows = runner.execute(item, grant(item), Path(directory) / 'run',
                sender=lambda *a: {}, credential=lambda: 'synthetic', clock=lambda: next(readings))
            self.assertEqual(rows[0]['errorKind'], 'TimeoutError')
            self.assertIsNone(rows[0]['costUSD'])


if __name__ == '__main__':
    unittest.main()
