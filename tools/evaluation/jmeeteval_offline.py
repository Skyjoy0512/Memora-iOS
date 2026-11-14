"""Pinned official checkers, offline only; never generates summaries or buys a judge call."""
import argparse
import asyncio
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
from unittest.mock import patch

VENDOR = Path(__file__).parent / 'vendor' / 'jmeeteval'
RULES = {'length_control:character_limit', 'length_control:proportion',
         'length_control:sentence_limit', 'output_constraint:no_punctuation',
         'writing_style:number_format'}


def load_data():
    manifest = json.loads((VENDOR / 'MANIFEST.json').read_text())
    for name, digest in manifest['sha256'].items():
        if hashlib.sha256((VENDOR / name).read_bytes()).hexdigest() != digest:
            raise ValueError('Pinned upstream file changed: ' + name)
    instructions = {row['id']: row for row in map(json.loads, (VENDOR / 'data/instructions.jsonl').read_text().splitlines())}
    records = list(map(json.loads, (VENDOR / 'data/transcripts.jsonl').read_text().splitlines()))
    assert len(records) == 197 and len({r['id'] for r in records}) == 197
    categories = Counter(instructions[key]['instruction_key'].split(':')[0]
                         for row in records for key in row['instruction_keys'])
    assert len(categories) == 16
    return manifest, instructions, records, categories


def denied(*args, **kwargs):
    raise RuntimeError('Network is disabled in Level 1 evaluation')


async def evaluate(responses, instructions, records):
    os.environ['PYTHON_DOTENV_DISABLED'] = '1'
    sys.path.insert(0, str(VENDOR))
    from jmeeteval.core.meeting_instructions_registry import MEETING_INSTRUCTION_DICT
    results = []
    indexed = {row['id']: row for row in records}
    seen = set()
    # Repeated blind runs use a separate invocation/artifact, never overwrite one ID.
    for response in responses:
        identifier = response['id']
        if identifier in seen or identifier not in indexed:
            raise ValueError('Duplicate or unknown response ID: ' + identifier)
        seen.add(identifier)
        row = indexed[identifier]
        if not isinstance(response['response'], str):
            raise ValueError('Response must be text')
        for key in row['instruction_keys']:
            instruction = instructions[key]
            checker_id = instruction['instruction_key']
            item = {'id': identifier, 'instruction': key, 'category': checker_id.split(':')[0],
                    'checker': checker_id, 'status': 'notEvaluated', 'score': None}
            if checker_id in RULES:
                checker = MEETING_INSTRUCTION_DICT[checker_id](checker_id)
                checker._cached_kwargs = dict(instruction['instruction_kwargs'])
                result = await checker.check_following(row['transcript'], response['response'])
                item.update(status='evaluated' if result.score is not None else 'unavailable', score=result.score)
            results.append(item)
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--responses', type=Path, help='Saved production-pipeline responses JSONL; never an API key')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(argv)
    manifest, instructions, records, categories = load_data()
    report = {'benchmark': 'J-MeetEval', 'mode': 'official-rule-subset-offline',
              'code': manifest['code'], 'dataset': manifest['dataset'], 'records': len(records),
              'categoryOccurrences': dict(sorted(categories.items())), 'apiRequests': 0,
              'overallOfficialScore': None, 'judgeStatus': 'notRun', 'results': []}
    if args.responses:
        supplied = [json.loads(line) for line in args.responses.read_text().splitlines() if line.strip()]
        with patch.object(socket.socket, 'connect', denied), patch.object(socket, 'create_connection', denied), patch.object(socket, 'getaddrinfo', denied):
            report['results'] = asyncio.run(evaluate(supplied, instructions, records))
        scores = [r['score'] for r in report['results'] if r['score'] is not None]
        report['ruleSubsetScore'] = sum(scores) / len(scores) if scores else None
        report['ruleChecksEvaluated'] = len(scores)
        report['notEvaluated'] = sum(r['score'] is None for r in report['results'])
    # Exclusive creation: an earlier measurement is evidence, not a scratch file.
    with args.output.open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({k: v for k, v in report.items() if k not in ('results', 'categoryOccurrences')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
