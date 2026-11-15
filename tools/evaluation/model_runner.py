"""Opt-in raw-request evaluator. Dry-run is offline and never reads a credential.

Requests must be exported with the actual source/instruction/settings. This is
not a second summary engine; it does not invent prompts, retry, run tools, infer
semantic scores, or label raw API measurements as production app measurements.
"""
import argparse
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import json
import multiprocessing
import os
from pathlib import Path
import time
import urllib.error
import urllib.request

REVISION = 'raw-request-runner-v1'
MAX_BYTES = 4 * 1024 * 1024
VARIANTS = {'single-pass', 'capacity-single-pass', 'hierarchical',
            'parallel-hierarchical', 'sot', 'cache-warm', 'cache-cold'}


def digest(value):
    return hashlib.sha256(value).hexdigest()


def positive_int(value, field, upper):
    if type(value) is not int or not 1 <= value <= upper:
        raise ValueError('Invalid ' + field)
    return value


def money(value, field, allow_zero=False):
    if type(value) not in (int, float, str):
        raise ValueError('Invalid ' + field)
    try:
        result = Decimal(str(value))
    except InvalidOperation as error:
        raise ValueError('Invalid ' + field) from error
    if not result.is_finite() or result < 0 or (not allow_zero and result == 0):
        raise ValueError('Invalid ' + field)
    return result


def https_endpoint(value):
    from urllib.parse import urlsplit
    parsed = urlsplit(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError('An explicit HTTPS endpoint without credentials/query is required')
    return value


def read_document(path):
    data = Path(path).read_bytes()
    if len(data) > MAX_BYTES:
        raise ValueError('Oversized evaluation document')
    return json.loads(data)


def validate(manifest):
    if manifest.get('schemaVersion') != 1:
        raise ValueError('Unknown evaluation schema')
    limits = manifest['limits']
    requests = positive_int(limits['requests'], 'request limit', 1024)
    tokens = positive_int(limits['tokens'], 'token limit', 100_000_000)
    seconds = positive_int(limits['seconds'], 'deadline', 7200)
    cap = money(limits['costUSD'], 'cost cap')
    rows = manifest['requests']
    if not isinstance(rows, list) or not rows or len(rows) > requests:
        raise ValueError('Request limit exceeded')
    ids = set()
    reserved_tokens, reserved_cost = 0, Decimal(0)
    plan = []
    for row in rows:
        run_id = row['runID']
        if not isinstance(run_id, str) or not run_id or len(run_id) > 128 or run_id in ids:
            raise ValueError('Missing or duplicate run ID')
        ids.add(run_id)
        if row['variant'] not in VARIANTS or row['cacheState'] not in ('cold', 'warm'):
            raise ValueError('Unknown comparison condition')
        positive_int(row['concurrency'], 'concurrency', 4)
        if not row.get('caseID') or not row.get('appCommit') or not row.get('promptVersion') or not row.get('datasetRevision'):
            raise ValueError('Missing reproducibility identity')
        source = row['source']
        if digest(json.dumps(source, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()) != row['sourceSHA256']:
            raise ValueError('Source fingerprint mismatch')
        body = row['body']
        if row['protocol'] not in ('chat-completions', 'anthropic-messages'):
            raise ValueError('Unsupported protocol')
        if not isinstance(body.get('model'), str) or not body['model'] or body.get('stream', False) is not False:
            raise ValueError('Explicit model and JSON response required')
        allowed = {'model', 'messages', 'system', 'max_tokens', 'max_completion_tokens',
                   'thinking', 'reasoning_effort', 'temperature', 'top_p', 'seed', 'stream',
                   'stream_options', 'stop', 'presence_penalty', 'frequency_penalty'}
        if set(body) - allowed or ('max_tokens' in body and 'max_completion_tokens' in body):
            raise ValueError('Unreviewed request options or competing ceilings')
        if not isinstance(body.get('system', ''), str):
            raise ValueError('Only acquired text is allowed in the evaluation request')
        if not isinstance(body.get('messages'), list) or not body['messages']:
            raise ValueError('Messages required')
        # Tools are data for capacity comparison only. No tool is ever executed.
        if any(not isinstance(message, dict) or set(message) - {'role', 'content'} or
               message.get('role') not in ('user', 'assistant', 'system') or
               not isinstance(message.get('content'), str) for message in body['messages']):
            raise ValueError('Remote/multimodal/server-tool inputs are outside this reviewed billing contract')
        output_field = 'max_tokens' if row['protocol'] == 'anthropic-messages' else row['outputLimitField']
        if output_field not in ('max_tokens', 'max_completion_tokens'):
            raise ValueError('Unknown output ceiling')
        output = positive_int(body.get(output_field), 'output ceiling', 1_000_000)
        contract = row['billingContract']
        if contract.get('outputIncludesReasoning') is not True or not contract.get('reviewID'):
            raise ValueError('A reviewed hard output/hidden-reasoning contract is required')
        encoded = json.dumps(body, ensure_ascii=False, separators=(',', ':')).encode()
        if len(encoded) > MAX_BYTES:
            raise ValueError('Oversized request')
        if digest(encoded) != row['instructionSHA256']:
            raise ValueError('Actual request fingerprint mismatch')
        # Deliberately conservative, explicitly labelled reservation, not usage.
        framing = positive_int(contract['framingUpperTokens'], 'framing reserve', 1_000_000)
        input_upper = len(encoded) + framing
        context = positive_int(contract['contextTokens'], 'context', 16_000_000)
        if input_upper + output > context:
            raise ValueError('Context ceiling exceeded')
        cost = (input_upper * money(contract['maximumInputUSDPerMillion'], 'input price', True) +
                output * money(contract['maximumOutputUSDPerMillion'], 'output price', True)) / Decimal(1_000_000)
        reserved_tokens += input_upper + output
        reserved_cost += cost
        plan.append({'runID': run_id, 'endpointSHA256': digest(https_endpoint(row['endpoint']).encode()),
                     'inputTokenUpperReservation': input_upper, 'outputTokenReservation': output,
                     'maximumRateCostReservationUSD': str(cost)})
    if reserved_tokens > tokens or reserved_cost > cap:
        raise ValueError('Aggregate token or cost reservation exceeds limit')
    return {'engineRevision': REVISION, 'requests': plan, 'requestCount': len(plan),
            'tokenReservation': reserved_tokens, 'costReservationUSD': str(reserved_cost),
            'deadlineSeconds': seconds, 'apiRequests': 0, 'measurementKind': 'plan-only'}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Evaluation redirects are forbidden')


def authorize(manifest, grant, now=None):
    now = now or datetime.now(timezone.utc)
    expires = datetime.fromisoformat(grant['expiresAt'].replace('Z', '+00:00'))
    if expires.tzinfo is None or not now < expires:
        raise ValueError('Expired evaluation grant')
    fingerprint = digest(json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode())
    if grant.get('manifestSHA256') != fingerprint or grant.get('sourceTransmissionApproved') is not True:
        raise ValueError('No approval for these exact evaluation inputs')
    guard = grant['spendGuard']
    # A client cannot guarantee vendor billing. A separately enforced prepaid
    # account/proxy is mandatory; a request timeout alone is not a spend guard.
    if guard.get('kind') not in ('provider-prepaid', 'billing-proxy') or not guard.get('receiptID'):
        raise ValueError('Externally enforced spend guard required')
    if money(guard['hardCapUSD'], 'external hard cap') > money(manifest['limits']['costUSD'], 'cost cap'):
        raise ValueError('External hard cap exceeds approved budget')
    if set(grant['endpoints']) != {row['endpoint'] for row in manifest['requests']}:
        raise ValueError('Endpoint grant mismatch')
    if grant.get('credentialEnvironment') != 'MEMORA_EVALUATION_API_KEY':
        raise ValueError('Only an independent evaluation credential is accepted')


def send(row, key, timeout):
    encoded = json.dumps(row['body'], ensure_ascii=False, separators=(',', ':')).encode()
    headers = {'Content-Type': 'application/json', 'Accept': 'application/json'}
    if row['protocol'] == 'anthropic-messages':
        headers.update({'x-api-key': key, 'anthropic-version': '2023-06-01'})
    else:
        headers['Authorization'] = 'Bearer ' + key
    request = urllib.request.Request(row['endpoint'], data=encoded, headers=headers, method='POST')
    opener = urllib.request.build_opener(NoRedirect())
    with opener.open(request, timeout=timeout) as response:
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError('Response byte ceiling exceeded')
    return json.loads(data)


def _send_worker(connection, row, key, timeout):
    try:
        connection.send(('ok', send(row, key, timeout)))
    except (ValueError, KeyError, TypeError, TimeoutError, OSError, EOFError) as error:
        connection.send(('error', {'kind': type(error).__name__,
            'status': error.code if isinstance(error, urllib.error.HTTPError) else None,
            'retryAfter': error.headers.get('Retry-After') if isinstance(error, urllib.error.HTTPError) else None}))
    finally:
        connection.close()


def bounded_send(row, key, timeout):
    # A socket idle timeout does not bound a slow trickling response. A child
    # process supplies an absolute deadline and is always joined/terminated.
    context = multiprocessing.get_context('spawn')
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(target=_send_worker, args=(sender, row, key, timeout))
    process.start()
    sender.close()
    try:
        if not receiver.poll(timeout):
            raise TimeoutError()
        kind, value = receiver.recv()
        if kind == 'error':
            if value['status'] is not None:
                raise urllib.error.HTTPError(row['endpoint'], value['status'], 'Evaluation request failed',
                    {'Retry-After': value['retryAfter']} if value['retryAfter'] else {}, None)
            raise OSError('Evaluation transport failed')
        return value
    finally:
        receiver.close()
        if process.is_alive():
            process.terminate()
        process.join(timeout=1)
        if process.is_alive():
            process.kill(); process.join()


def execute(manifest, grant, output, sender=bounded_send, credential=None, clock=time.monotonic):
    plan = validate(manifest)
    authorize(manifest, grant)
    # Refuse to overwrite earlier evidence, before reading any credential.
    output = Path(output)
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    (output / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    key = credential() if credential else os.environ.get('MEMORA_EVALUATION_API_KEY')
    if not isinstance(key, str) or not key or '\n' in key or '\r' in key:
        raise ValueError('Independent evaluation credential missing')
    started = clock()
    results = []
    # Sequential raw requests deliberately do not claim app concurrency, warm
    # artifact-cache or multi-stage pipeline timings. Those need native runs.
    for row in manifest['requests']:
        remaining = plan['deadlineSeconds'] - (clock() - started)
        if remaining <= 0:
            break
        before = clock()
        result = {k: v for k, v in row.items() if k not in ('body', 'source', 'endpoint', 'billingContract')}
        result.update(engineRevision=REVISION, endpointSHA256=digest(row['endpoint'].encode()),
                      measurementKind='raw-provider-request', status='failed', usage=None,
                      summarySeconds=None, totalSeconds=None, costUSD=None, costKind='unknown',
                      timeToFirstToken=None, reasoningSeconds=None, persistenceSeconds=None,
                      transcriptionSeconds=None, cpu=None, peakMemory=None, batteryImpact=None,
                      thermalState=None, apiRequests=1)
        try:
            response = sender(row, key, min(remaining, 300))
            elapsed = clock() - before
            if elapsed > remaining:
                raise TimeoutError()
            if row['protocol'] == 'anthropic-messages':
                valid = response.get('stop_reason') == 'end_turn' and all(b.get('type') in ('text', 'thinking', 'redacted_thinking') for b in response.get('content', []))
                text = ''.join(b.get('text', '') for b in response.get('content', []) if b.get('type') == 'text')
            else:
                choices = response.get('choices', [])
                message = choices[0].get('message', {}) if choices else {}
                valid = bool(choices and choices[0].get('finish_reason') == 'stop' and not message.get('tool_calls') and not message.get('refusal'))
                text = message.get('content', '')
            if not valid or not isinstance(text, str) or not text.strip():
                raise ValueError('Non-terminal, refused or tool response')
            result.update(status='completed', requestSeconds=elapsed, usage=response.get('usage'), output=text)
        except (ValueError, KeyError, TypeError, TimeoutError, OSError, EOFError) as error:
            # Error strings can contain credentials, endpoint paths or input.
            result.update(errorKind=type(error).__name__, requestSeconds=clock() - before)
            if isinstance(error, urllib.error.HTTPError):
                result['httpStatus'] = error.code
                result['retryAfter'] = error.headers.get('Retry-After')
        results.append(result)
        with (output / 'runs.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(result, ensure_ascii=False) + '\n')
        if result['status'] != 'completed':
            break # No retry, including 429, timeout, unknown billing or bad output.
    (output / 'result.json').write_text(json.dumps({'planned': len(plan['requests']), 'executed': len(results),
        'completed': sum(r['status'] == 'completed' for r in results), 'automaticAdoption': False}, indent=2) + '\n')
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--grant', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    manifest = read_document(args.manifest)
    if args.execute:
        if not args.grant:
            parser.error('--execute requires a manifest-bound grant and external spend guard')
        results = execute(manifest, read_document(args.grant), args.output)
        return 0 if len(results) == len(manifest['requests']) and all(r['status'] == 'completed' for r in results) else 1
    plan = validate(manifest)
    with args.output.open('x') as stream:
        json.dump(plan, stream, indent=2)
        stream.write('\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
