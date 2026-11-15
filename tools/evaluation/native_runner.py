"""Opt-in native Swift orchestration/streaming evaluator; offline by default.

The driver never receives a real credential or network permission. This broker
validates and reserves every generated request, including warmups/continuations,
before a child process may send it. Host SQLite persistence is explicitly not
the iOS record-save boundary. No results from this runner enable a release gate.
"""
import argparse
import base64
from datetime import datetime, timezone
from decimal import Decimal
import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import queue
import re
import subprocess
import threading
import time
import urllib.error
import urllib.request

import model_runner as raw
from quality_metrics import performance, summary_measurements

ROOT = Path(__file__).resolve().parents[2]
REVISION = 'native-host-streaming-v1'
MAX_LINE = 8 * 1024 * 1024


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def source_snapshot():
    spec = importlib.util.spec_from_file_location('quality_guard', ROOT / 'tools/checks/run-quality-checks.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.source_snapshot()


def validate(manifest, driver):
    if manifest.get('schemaVersion') != 1 or manifest.get('engineRevision') != REVISION:
        raise ValueError('Unknown native evaluation contract')
    if raw.digest(canonical(manifest['source'])) != manifest['sourceSHA256']:
        raise ValueError('Source fingerprint mismatch')
    if raw.digest(Path(driver).read_bytes()) != manifest['driverSHA256']:
        raise ValueError('Compiled driver fingerprint mismatch')
    if source_snapshot()['sha256'] != manifest['sourceCodeSHA256']:
        raise ValueError('Code fingerprint mismatch; rebuild and review the manifest')
    provenance = raw.read_document(str(driver) + '.build.json')
    if provenance.get('sourceGuardUnchanged') is not True or provenance.get('driverSHA256') != manifest['driverSHA256'] or provenance.get('sourceCodeSHA256') != manifest['sourceCodeSHA256']:
        raise ValueError('Driver was not built from the reviewed source snapshot')
    raw.https_endpoint(manifest['endpoint'])
    for field in ('appCommit', 'datasetRevision', 'promptVersion', 'caseID'):
        if not isinstance(manifest.get(field), str) or not manifest[field]:
            raise ValueError('Missing ' + field)
    llm = manifest['llm']
    if set(llm) - {'provider', 'modelID', 'endpoint'} or not llm.get('modelID'):
        raise ValueError('Only explicit provider/model/optional base endpoint are allowed')
    if llm.get('endpoint'):
        raw.https_endpoint(llm['endpoint'])
    limits = manifest['limits']
    raw.positive_int(limits['requests'], 'requests', 1024)
    raw.positive_int(limits['tokens'], 'tokens', 100_000_000)
    raw.positive_int(limits['seconds'], 'seconds', 7200)
    raw.money(limits['costUSD'], 'cost cap')
    contract = manifest['billingContract']
    if not contract.get('reviewID') or contract.get('outputIncludesReasoning') is not True:
        raise ValueError('Reviewed output and hidden reasoning ceiling required')
    raw.positive_int(contract['implicitOutputCeiling'], 'implicit output', 1_000_000)
    raw.positive_int(contract['contextTokens'], 'context', 16_000_000)
    raw.positive_int(contract['framingUpperTokens'], 'framing', 1_000_000)
    raw.money(contract['maximumInputUSDPerMillion'], 'input price', True)
    raw.money(contract['maximumOutputUSDPerMillion'], 'output price', True)
    runs = manifest['runs']
    if not isinstance(runs, list) or not 1 <= len(runs) <= 1024:
        raise ValueError('Bounded run list required')
    ids = set()
    for run in runs:
        if set(run) - {'runID', 'variant', 'concurrency', 'partCapacity', 'repetition'}:
            raise ValueError('Unreviewed run option')
        if not isinstance(run.get('runID'), str) or not run['runID'] or len(run['runID']) > 128 or run['runID'] in ids:
            raise ValueError('Missing or duplicate run identity')
        ids.add(run['runID'])
        if run['variant'] not in raw.VARIANTS:
            raise ValueError('Unknown variant')
        width = raw.positive_int(run['concurrency'], 'concurrency', 4)
        raw.positive_int(run['repetition'], 'repetition', 100)
        hierarchical = run['variant'] in ('hierarchical', 'parallel-hierarchical', 'cache-warm', 'cache-cold')
        if hierarchical:
            raw.positive_int(run.get('partCapacity'), 'part capacity', 16_000_000)
        elif run.get('partCapacity') is not None:
            raise ValueError('Single-source routes cannot carry an artificial partition cap')
        if run['variant'] in ('single-pass', 'capacity-single-pass', 'hierarchical') and width != 1:
            raise ValueError('Serial comparison requires concurrency one')
    return {'engineRevision': REVISION, 'measurementKind': 'plan-only', 'apiRequests': 0,
            'runCount': len(runs), 'requestsUpperLimit': limits['requests'],
            'warmupsBudgeted': True, 'automaticAdoption': False,
            'persistenceBoundary': 'host-summary-document'}


def authorize(manifest, grant):
    # Reuse the exact-manifest / dedicated-key / external-hard-cap contract.
    surrogate = dict(manifest, requests=[{'endpoint': manifest['endpoint']}])
    surrogate_grant = dict(grant, manifestSHA256=raw.digest(canonical(surrogate)))
    if grant.get('manifestSHA256') != raw.digest(canonical(manifest)):
        raise ValueError('Native manifest grant mismatch')
    raw.authorize(surrogate, surrogate_grant)


class Ledger:
    def __init__(self, manifest):
        self.manifest = manifest
        self.lock = threading.Lock()
        self.requests = self.tokens = 0
        self.cost = Decimal(0)
        self.stopped = False

    def reserve(self, event, run):
        if event['endpoint'] != self.manifest['endpoint'] or not isinstance(event['body'], dict):
            raise ValueError('Unapproved endpoint or request')
        original = event['body']
        if original.get('model') != self.manifest['llm']['modelID'] or original.get('stream') is not True:
            raise ValueError('Model/stream contract changed')
        body = dict(original, stream=False)
        # Do not alter the actual request. A provider's reviewed implicit ceiling
        # may be used only for a conservative reservation when it omits a cap.
        cap = 'max_tokens' if self.manifest['llm']['provider'] == 'anthropic' else (
            'max_completion_tokens' if 'max_completion_tokens' in body else 'max_tokens')
        if not any(k in body for k in ('max_tokens', 'max_completion_tokens')):
            body[cap] = self.manifest['billingContract']['implicitOutputCeiling']
        if body[cap] > self.manifest['billingContract']['implicitOutputCeiling']:
            raise ValueError('Output ceiling exceeds reviewed billing contract')
        row = dict(run, caseID=self.manifest['caseID'], provider=self.manifest['llm']['provider'],
            protocol='anthropic-messages' if self.manifest['llm']['provider'] == 'anthropic' else 'chat-completions',
            endpoint=event['endpoint'], source=self.manifest['source'], sourceSHA256=self.manifest['sourceSHA256'],
            body=body, instructionSHA256=raw.digest(json.dumps(body, ensure_ascii=False, separators=(',', ':')).encode()),
            appCommit=self.manifest['appCommit'], promptVersion=self.manifest['promptVersion'],
            datasetRevision=self.manifest['datasetRevision'], cacheState='warm' if run['variant'] == 'cache-warm' else 'cold',
            outputLimitField=cap, billingContract=self.manifest['billingContract'])
        result = raw.validate({'schemaVersion': 1, 'limits': self.manifest['limits'], 'requests': [row]})
        with self.lock:
            limits = self.manifest['limits']
            cost = Decimal(result['costReservationUSD'])
            if self.stopped or self.requests + 1 > limits['requests'] or self.tokens + result['tokenReservation'] > limits['tokens'] or self.cost + cost > raw.money(limits['costUSD'], 'cost cap'):
                self.stopped = True
                raise ValueError('Aggregate reservation exhausted or previous failure')
            self.requests += 1
            self.tokens += result['tokenReservation']
            self.cost += cost
        return result['requests'][0]

    def stop(self):
        with self.lock:
            self.stopped = True


def matrix_report(results, manifest):
    cohorts = {}
    for result in results:
        key = (result['variant'], result['concurrency'], result['phase'])
        cohorts.setdefault(key, []).append(result)
    rows = []
    for (variant, width, phase), samples in sorted(cohorts.items()):
        completed = [dict(sample, **summary_measurements(sample.get('diagnostics', {}), manifest['llm']['provider']))
                     for sample in samples if sample['status'] == 'completed']
        rows.append({'variant': variant, 'concurrency': width, 'phase': phase, 'attempts': len(samples),
                     'failures': len(samples) - len(completed), 'failureRate': (len(samples) - len(completed)) / len(samples),
                     'successfulPerformance': performance(completed), 'semanticQuality': None})
    return {'schemaVersion': 1, 'engineRevision': REVISION, 'sourceSHA256': manifest['sourceSHA256'],
            'sourceCodeSHA256': manifest['sourceCodeSHA256'], 'provider': manifest['llm']['provider'],
            'inferenceKinds': sorted({r.get('inferenceKind', 'unknown') for r in results}),
            'model': manifest['llm']['modelID'], 'endpointSHA256': raw.digest(manifest['endpoint'].encode()),
            'automaticAdoption': False, 'persistenceBoundary': 'host-summary-document', 'cohorts': rows}


def safe_retry_after(value):
    if not isinstance(value, str) or len(value) > 128:
        return ''
    if re.fullmatch(r'[0-9]{1,9}', value):
        return value
    try:
        from email.utils import parsedate_to_datetime, format_datetime
        parsed = parsedate_to_datetime(value)
        return format_datetime(parsed.astimezone(timezone.utc), usegmt=True) if parsed.tzinfo else ''
    except (ValueError, TypeError, OverflowError):
        return ''


def _stream_worker(connection, endpoint, body, key, anthropic, timeout):
    try:
        headers = {'Content-Type': 'application/json', 'Accept': 'text/event-stream', 'Accept-Encoding': 'identity'}
        headers.update({'x-api-key': key, 'anthropic-version': '2023-06-01'} if anthropic else {'Authorization': 'Bearer ' + key})
        request = urllib.request.Request(endpoint, data=json.dumps(body, ensure_ascii=False, separators=(',', ':')).encode(), headers=headers, method='POST')
        with urllib.request.build_opener(raw.NoRedirect()).open(request, timeout=timeout) as response:
            connection.send({'kind': 'headers', 'status': response.status,
                'headers': {'Content-Type': response.headers.get('Content-Type', '')}})
            size = 0
            while True:
                chunk = response.read1(8192)
                if not chunk:
                    break
                size += len(chunk)
                ceiling = 2 if 'application/json' in response.headers.get('Content-Type', '') else 32
                if size > ceiling * 1024 * 1024:
                    raise ValueError('Response limit exceeded')
                connection.send({'kind': 'bytes', 'data': base64.b64encode(chunk).decode()})
        connection.send({'kind': 'end'})
    except urllib.error.HTTPError as error:
        connection.send({'kind': 'headers', 'status': error.code, 'headers': {
            'Content-Type': 'text/event-stream', 'Retry-After': safe_retry_after(error.headers.get('Retry-After', ''))}})
        connection.send({'kind': 'error'})
    except (ValueError, TypeError, OSError, TimeoutError):
        connection.send({'kind': 'error'})
    finally:
        connection.close()


def live_stream(event, manifest, key, deadline, cancelled):
    context = multiprocessing.get_context('spawn')
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(target=_stream_worker, args=(sender, event['endpoint'], event['body'], key,
        manifest['llm']['provider'] == 'anthropic', max(0.001, min(300, deadline - time.monotonic()))))
    process.start()
    sender.close()
    try:
        while not cancelled.is_set():
            if time.monotonic() >= deadline:
                yield {'kind': 'error', 'timedOut': True}
                return
            if receiver.poll(0.05):
                try:
                    value = receiver.recv()
                except EOFError:
                    yield {'kind': 'error'}
                    return
                yield value
                if value['kind'] in ('end', 'error'):
                    return
            elif not process.is_alive():
                yield {'kind': 'error'}
                return
    finally:
        receiver.close()
        if process.is_alive():
            process.terminate()
        process.join(timeout=1)
        if process.is_alive():
            process.kill()
            process.join()


def run_driver(manifest, run, driver, output, ledger, key, deadline, streamer=live_stream, reauthorize=lambda: None):
    output.mkdir(mode=0o700)
    config = {'source': manifest['source'], 'llm': dict(manifest['llm'], supportsToolCalling=True),
              'options': {k: v for k, v in run.items() if k in ('variant', 'concurrency', 'partCapacity')},
              'database': (output / 'store.sqlite').as_uri()}
    config_path = output / 'configuration.json'
    config_path.write_bytes(canonical(config))
    write_lock, evidence_lock, active_lock = threading.Lock(), threading.Lock(), threading.Lock()
    stop_reader = threading.Event()
    active, threads, results = {}, [], []
    lines = queue.Queue(maxsize=16)
    env = {'PATH': os.defpath, 'TZ': 'UTC', 'LANG': 'en_US.UTF-8', 'TMPDIR': str(output) + '/', 'SWIFT_BACKTRACE': 'enable=no'}
    with (output / 'driver.log').open('xb') as log, subprocess.Popen([str(driver), str(config_path)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, env=env) as process:
        def reader():
            while True:
                try:
                    line = process.stdout.readline(MAX_LINE + 1)
                except (OSError, ValueError):
                    return
                while not stop_reader.is_set():
                    try:
                        lines.put(line, timeout=0.1)
                        break
                    except queue.Full:
                        continue
                if stop_reader.is_set():
                    return
                if not line or len(line) > MAX_LINE:
                    return
        reader_thread = threading.Thread(target=reader, daemon=True)
        reader_thread.start()

        def deliver(event):
            with write_lock:
                try:
                    process.stdin.write(canonical(event) + b'\n')
                    process.stdin.flush()
                except (BrokenPipeError, OSError, ValueError):
                    ledger.stop()

        def record(event):
            with evidence_lock, (output / 'requests.jsonl').open('a') as stream:
                stream.write(json.dumps(event, ensure_ascii=False) + '\n')

        def send(event, cancelled):
            began = time.monotonic()
            status = 'unknown'
            try:
                reauthorize()
                reservation = ledger.reserve(event, run)
                record({'id': event['id'], 'status': 'reserved', 'bodySHA256': raw.digest(canonical(event['body'])),
                        'phase': event['_phase'], 'reservation': reservation})
                for response in streamer(event, manifest, key, min(deadline, began + 300), cancelled):
                    if response['kind'] == 'headers' and response['status'] >= 400:
                        ledger.stop()
                        record({'id': event['id'], 'httpStatus': response['status'], 'retryAfter': response['headers'].get('Retry-After')})
                    if response['kind'] == 'error':
                        ledger.stop()
                        status = 'failed'
                    elif response['kind'] == 'end':
                        status = 'transport-completed'
                    if response['kind'] in ('end', 'error'):
                        with active_lock:
                            active.pop(event['id'], None)
                    deliver(dict(response, id=event['id']))
            except (ValueError, KeyError, TypeError, OSError):
                ledger.stop()
                status = 'refused-or-transport-failed'
                deliver({'kind': 'error', 'id': event['id']})
            finally:
                record({'id': event['id'], 'status': status, 'requestSeconds': time.monotonic() - began,
                        'costUSD': None, 'costKind': 'unknown'})
                with active_lock:
                    active.pop(event['id'], None)

        phase = ['unknown']
        started = time.monotonic()
        try:
            while True:
                if time.monotonic() >= deadline:
                    raise TimeoutError()
                try:
                    line = lines.get(timeout=min(0.1, max(0.001, deadline - time.monotonic())))
                except queue.Empty:
                    continue
                if not line:
                    break
                if len(line) > MAX_LINE:
                    raise ValueError('Driver frame too large')
                event = json.loads(line)
                kind = event['kind']
                if kind == 'request':
                    event['_phase'] = phase[0]
                    with active_lock:
                        if len(active) >= run['concurrency'] or event['id'] in active:
                            raise ValueError('Native request concurrency exceeded manifest')
                        cancel = threading.Event()
                        active[event['id']] = cancel
                    thread = threading.Thread(target=send, args=(event, cancel), daemon=True)
                    threads.append(thread)
                    thread.start()
                elif kind == 'cancel':
                    with active_lock:
                        if event['id'] in active:
                            active[event['id']].set()
                elif kind == 'phase':
                    phase[0] = event['phase']
                elif kind == 'result':
                    event.update(runID=run['runID'], variant=run['variant'], concurrency=run['concurrency'],
                        repetition=run['repetition'], sourceSHA256=manifest['sourceSHA256'],
                        model=manifest['llm']['modelID'], sourceCodeSHA256=manifest['sourceCodeSHA256'],
                        inferenceKind='real-provider' if streamer is live_stream else 'mock')
                    results.append(event)
                    with (output / 'runs.jsonl').open('a') as stream:
                        stream.write(json.dumps(event, ensure_ascii=False) + '\n')
                    if event['status'] != 'completed':
                        ledger.stop()
                else:
                    raise ValueError('Unknown driver frame')
            process.wait(timeout=max(0.001, deadline - time.monotonic()))
        finally:
            stop_reader.set()
            with active_lock:
                for cancelled in active.values():
                    cancelled.set()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            process.stdin.close()
            process.stdout.close()
            for thread in threads:
                thread.join(timeout=3)
        expected = ['warmup', 'measured'] if run['variant'] == 'cache-warm' else ['measured']
        if process.returncode != 0 or [r['phase'] for r in results] != expected or any(r['status'] != 'completed' for r in results):
            ledger.stop()
        (output / 'result.json').write_bytes(canonical({'processExitCode': process.returncode,
            'phases': len(results), 'driverWallSeconds': time.monotonic() - started, 'automaticAdoption': False}))
    return results


def execute(manifest, grant, driver, output, streamer=live_stream, credential=None):
    plan = validate(manifest, driver)
    authorize(manifest, grant)
    output = Path(output).resolve()
    if output == ROOT or ROOT in output.parents:
        raise ValueError('Evaluation output must be outside the repository')
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    (output / 'plan.json').write_bytes(canonical(plan))
    baseline = source_snapshot()
    key = credential() if credential else os.environ.get('MEMORA_EVALUATION_API_KEY')
    if not isinstance(key, str) or not key or '\n' in key or '\r' in key:
        raise ValueError('Independent evaluation credential missing')
    ledger = Ledger(manifest)
    deadline = time.monotonic() + manifest['limits']['seconds']
    results = []
    unchanged = False
    try:
        for index, run in enumerate(manifest['runs']):
            authorize(manifest, grant)
            if source_snapshot() != baseline or raw.digest(Path(driver).read_bytes()) != manifest['driverSHA256']:
                raise ValueError('Code or driver changed during evaluation')
            if ledger.stopped or time.monotonic() >= deadline:
                break
            results.extend(run_driver(manifest, run, driver, output / ('run-' + str(index + 1)), ledger, key, deadline,
                                      streamer, lambda: authorize(manifest, grant)))
        if source_snapshot() != baseline:
            raise ValueError('Code changed; evaluation results invalid')
        unchanged = True
    except BaseException:
        ledger.stop()
        raise
    finally:
        matrix = matrix_report(results, manifest)
        matrix['sourceGuardUnchanged'] = unchanged
        matrix['validity'] = 'source-unchanged' if unchanged else 'invalid-or-incomplete'
        (output / 'matrix.json').write_bytes(canonical(matrix))
        (output / 'result.json').write_bytes(canonical({'runs': len(results), 'requestReservations': ledger.requests,
            'tokenUpperReservation': ledger.tokens, 'maximumRateCostUpperReservationUSD': str(ledger.cost),
            'costUSD': None, 'costKind': 'unknown', 'automaticAdoption': False,
            'stopped': ledger.stopped, 'measurementKind': 'native-host-streaming',
            'sourceGuardUnchanged': unchanged, 'inferenceKind': 'real-provider' if streamer is live_stream else 'mock',
            'persistenceBoundary': 'host-summary-document'}))
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--driver', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--grant', type=Path)
    args = parser.parse_args()
    manifest = raw.read_document(args.manifest)
    if not args.execute:
        plan = validate(manifest, args.driver)
        with args.output.open('x') as stream:
            json.dump(plan, stream, indent=2)
            stream.write('\n')
        return 0
    if not args.grant:
        parser.error('--execute requires an exact-manifest grant and independent external hard cap')
    results = execute(manifest, raw.read_document(args.grant), args.driver.resolve(), args.output)
    return 0 if sum(r['phase'] == 'measured' and r['status'] == 'completed' for r in results) == len(manifest['runs']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
