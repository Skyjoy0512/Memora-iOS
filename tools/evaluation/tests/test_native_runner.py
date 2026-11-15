import copy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import native_runner as runner


def manifest(driver):
    source = {'id': str(uuid.UUID(int=1)), 'title': 'Synthetic review', 'date': '2026-01-01T00:00:00Z',
        'duration': 3600, 'participantNames': [], 'preferences': {'length': 'detailed', 'processingMode': 'balanced'},
        'transcript': [{'id': str(uuid.UUID(int=i + 10)), 'speaker': 'A', 'speakerIsCertain': False,
                        'timestamp': i * 600, 'text': ('Retain conditions and the corrected budget. ' * 30)} for i in range(4)]}
    return {'schemaVersion': 1, 'engineRevision': runner.REVISION, 'source': source,
        'sourceSHA256': runner.raw.digest(runner.canonical(source)), 'driverSHA256': runner.raw.digest(Path(driver).read_bytes()),
        'sourceCodeSHA256': runner.source_snapshot()['sha256'], 'endpoint': 'https://api.deepseek.com/chat/completions',
        'llm': {'provider': 'deepSeek', 'modelID': 'deepseek-v4-pro'}, 'appCommit': 'synthetic-check',
        'datasetRevision': 'synthetic-v1', 'promptVersion': 'production-current', 'caseID': 'synthetic-only',
        'limits': {'requests': 100, 'tokens': 100_000_000, 'seconds': 60, 'costUSD': '10'},
        'billingContract': {'reviewID': 'mock-only', 'outputIncludesReasoning': True, 'implicitOutputCeiling': 393216,
            'contextTokens': 1000000, 'framingUpperTokens': 2048, 'maximumInputUSDPerMillion': '0.1',
            'maximumOutputUSDPerMillion': '0.2'},
        'runs': [{'runID': 'single', 'variant': 'single-pass', 'concurrency': 1, 'repetition': 1}]}


def grant(value):
    return {'expiresAt': (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat(),
        'manifestSHA256': runner.raw.digest(runner.canonical(value)), 'sourceTransmissionApproved': True,
        'credentialEnvironment': 'MEMORA_EVALUATION_API_KEY', 'endpoints': [value['endpoint']],
        'spendGuard': {'kind': 'billing-proxy', 'receiptID': 'mock-only', 'hardCapUSD': value['limits']['costUSD']}}


def streaming_reply(event, manifest, key, deadline, cancelled):
    if key != 'mock-independent':
        raise AssertionError('Unexpected credential')
    user = event['body']['messages'][-1]['content']
    segment = re.search(r'\]\s+(S\d+)\s+A\d+:\s+([^\n]+)', user)
    original = re.search(r'\[segmentID=([A-Fa-f0-9-]+)\][^\n]*?:\s+([^\n]+)', user)
    found = segment or original
    reference = {'sourceSegmentID': found[1], 'quote': found[2][:42]} if found else None
    if '"schemaVersion":1,"overview"' in user:
        text = json.dumps({'schemaVersion': 1, 'overview': 'Synthetic overview.', 'sections': [
            {'id': 'conditions', 'title': 'Conditions', 'sourceSegmentIDs': [reference['sourceSegmentID']]},
            {'id': 'budget', 'title': 'Budget', 'sourceSegmentIDs': [reference['sourceSegmentID']]}],
            'extraction': {'templateID': 'builtin.detailedOverview', 'decisions': [], 'actions': [], 'knowledge': {
                'schemaVersion': 1, 'selectedProfileIDs': [], 'contentType': 'meeting', 'topics': [
                    {'id': 'conditions', 'title': 'Conditions'}, {'id': 'budget', 'title': 'Budget'}],
                'facts': [], 'coverage': []}}})
    elif 'sourceReferencesは空配列' in user:
        text = json.dumps({'notes': 'Retain conditions and the corrected budget.', 'sourceReferences': [reference]})
    else:
        text = 'Retain conditions and the corrected budget.'
    payload = ('data: ' + json.dumps({'choices': [{'delta': {'content': text}, 'finish_reason': None}]}) + '\n\n' +
        'data: ' + json.dumps({'choices': [{'delta': {}, 'finish_reason': 'stop'}],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 10}}) + '\n\n' + 'data: [DONE]\n\n').encode()
    yield {'kind': 'headers', 'status': 200, 'headers': {'Content-Type': 'text/event-stream'}}
    # Exercise fragmented byte transport and the real stream decoder.
    for offset in range(0, len(payload), 113):
        if cancelled.is_set():
            return
        yield {'kind': 'bytes', 'data': runner.base64.b64encode(payload[offset:offset + 113]).decode()}
    yield {'kind': 'end'}


class NativeRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.driver = Path(self.temp.name) / 'driver'
        self.driver.write_bytes(b'not-executed')
        self.value = manifest(self.driver)
        Path(str(self.driver) + '.build.json').write_bytes(runner.canonical(dict(
            sourceGuardUnchanged=True, driverSHA256=self.value['driverSHA256'], sourceCodeSHA256=self.value['sourceCodeSHA256'])))

    def test_offline_preflight_does_not_read_credentials_or_network(self):
        with patch('urllib.request.build_opener', side_effect=AssertionError('network')), patch.dict('os.environ', {'MEMORA_EVALUATION_API_KEY': 'never-read'}):
            result = runner.validate(self.value, self.driver)
        self.assertEqual(result['apiRequests'], 0)
        self.assertFalse(result['automaticAdoption'])

    def test_identity_and_matrix_conditions(self):
        changes = [lambda v: v.update(sourceSHA256='changed'), lambda v: v.update(driverSHA256='changed'),
            lambda v: v.update(sourceCodeSHA256='changed'), lambda v: v.update(endpoint='http://invalid.test'),
            lambda v: v['runs'][0].update(concurrency=4), lambda v: v['runs'][0].update(variant='unknown'),
            lambda v: v['runs'][0].update(partCapacity=1000), lambda v: v['llm'].update(credentialAccount='daily-key'),
            lambda v: v['billingContract'].update(outputIncludesReasoning=False)]
        for change in changes:
            value = copy.deepcopy(self.value)
            change(value)
            with self.subTest(change=change), self.assertRaises(ValueError):
                runner.validate(value, self.driver)

    def test_exact_permission_and_external_cap(self):
        approved = grant(self.value)
        runner.authorize(self.value, approved)
        for update in ({'sourceTransmissionApproved': False}, {'manifestSHA256': 'changed'},
                       {'spendGuard': {'kind': 'client-timeout'}}, {'expiresAt': '2000-01-01T00:00:00Z'}):
            with self.subTest(update=update), self.assertRaises((ValueError, KeyError)):
                runner.authorize(self.value, dict(approved, **update))

    def test_retry_after_does_not_store_arbitrary_provider_text(self):
        self.assertEqual(runner.safe_retry_after('120'), '120')
        self.assertEqual(runner.safe_retry_after('Mon, 01 Jan 2024 00:00:00 GMT'), 'Mon, 01 Jan 2024 00:00:00 GMT')
        self.assertEqual(runner.safe_retry_after('echoed-private-value'), '')

    def test_aggregate_reservations_stop_before_send(self):
        self.value['limits']['requests'] = 1
        ledger = runner.Ledger(self.value)
        event = {'endpoint': self.value['endpoint'], 'body': {'model': 'deepseek-v4-pro', 'stream': True,
            'messages': [{'role': 'user', 'content': 'synthetic'}]}}
        original = copy.deepcopy(event)
        ledger.reserve(event, self.value['runs'][0])
        self.assertEqual(event, original, 'Reservation changed the real request or output budget')
        with self.assertRaises(ValueError):
            ledger.reserve(event, self.value['runs'][0])
        self.assertEqual(ledger.requests, 1)
        self.assertTrue(ledger.stopped)

    def test_changed_source_refuses_execution_and_retains_failure_evidence(self):
        baseline = {'sha256': self.value['sourceCodeSHA256']}
        output = Path(self.temp.name) / 'changed'
        with patch.object(runner, 'source_snapshot', side_effect=[baseline, baseline, {'sha256': 'changed'}]), self.assertRaises(ValueError):
            runner.execute(self.value, grant(self.value), self.driver, output, credential=lambda: 'mock-independent')
        result = json.loads((output / 'result.json').read_text())
        self.assertFalse(result['sourceGuardUnchanged'])
        self.assertEqual(result['requestReservations'], 0)

    def test_matrix_keeps_missing_metrics_unknown_and_failure_separate(self):
        rows = [{'variant': 'single-pass', 'concurrency': 1, 'phase': 'measured', 'status': 'completed', 'summarySeconds': n}
                for n in (1, 2, 10)]
        rows.append(dict(rows[0], status='failed', summarySeconds=0.001))
        matrix = runner.matrix_report(rows, self.value)['cohorts'][0]
        self.assertEqual(matrix['failureRate'], 0.25)
        self.assertEqual(matrix['successfulPerformance']['summarySeconds']['p95'], 10)
        self.assertIsNone(matrix['successfulPerformance']['costUSD']['p50'])
        self.assertIsNone(matrix['semanticQuality'])


def integration(driver, output):
    value = manifest(driver)
    value['runs'] = []
    for index, variant in enumerate(sorted(runner.raw.VARIANTS)):
        run = {'runID': 'variant-' + str(index), 'variant': variant, 'concurrency': 1 if variant in
            ('single-pass', 'capacity-single-pass', 'hierarchical') else 2, 'repetition': 1}
        if variant in ('hierarchical', 'parallel-hierarchical', 'cache-cold', 'cache-warm'):
            run['partCapacity'] = 1600
        value['runs'].append(run)
    results = runner.execute(value, grant(value), Path(driver), output, streamer=streaming_reply,
        credential=lambda: 'mock-independent')
    assert len(results) == 8, [(r['variant'], r['phase'], r['status'], r.get('failure')) for r in results]
    assert all(r['status'] == 'completed' and r['inferenceKind'] == 'mock' for r in results), [(r['variant'], r.get('failure')) for r in results]
    for result in results:
        assert result['summary']['markdown']
        assert result['diagnostics']['saveSeconds'] >= 0
        assert result['persistenceBoundary'] == 'host-summary-document'
        if result['variant'] in ('single-pass', 'capacity-single-pass'):
            assert result['diagnostics']['requestCount'] == 1
        if result['variant'] == 'sot':
            assert result['diagnostics']['requestCount'] == 3
    warm = next(r for r in results if r['variant'] == 'cache-warm' and r['phase'] == 'measured')
    assert warm['diagnostics']['artifactCacheHits'] > 0
    assert warm['diagnostics']['requestCount'] == 1
    data = json.loads((Path(output) / 'result.json').read_text())
    assert data['sourceGuardUnchanged'] and data['costUSD'] is None
    assert not data['automaticAdoption'] and data['inferenceKind'] == 'mock'
    print('Native seven-way orchestration + SSE + SQLite: PASS; 8 phases, budgeted warmup, mock inference only, zero external API requests')
    for error in ('429', 'timeout', 'budget', 'permission'):
        failed = manifest(driver)
        failed['runs'] = [{'runID': 'failure', 'variant': 'hierarchical', 'partCapacity': 1600,
                           'concurrency': 1, 'repetition': 1}]
        if error == 'budget':
            failed['limits']['requests'] = 1
        permission = grant(failed)
        sent = []

        def failure_stream(event, value, key, deadline, cancelled):
            sent.append(event['id'])
            if error == '429':
                yield {'kind': 'headers', 'status': 429, 'headers': {'Retry-After': '120'}}
                yield {'kind': 'error'}
            elif error == 'timeout':
                yield {'kind': 'error', 'timedOut': True}
            else:
                if error == 'permission':
                    permission['expiresAt'] = '2000-01-01T00:00:00Z'
                yield from streaming_reply(event, value, key, deadline, cancelled)

        failures = runner.execute(failed, permission, Path(driver), Path(str(output) + '-' + error),
            streamer=failure_stream, credential=lambda: 'mock-independent')
        assert len(sent) == 1 and len(failures) == 1 and failures[0]['status'] == 'failed', (error, sent, failures)
        assert 'summary' not in failures[0]
    print('Native 429/timeout/aggregate budget/expired permission: PASS; one sent mock request, no repair/merge/retry or saved summary')


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--integration':
        integration(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        unittest.main()
