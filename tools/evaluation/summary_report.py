"""Offline paired quality/performance reports from independently annotated runs.

This command never generates summaries, reads credentials, or invokes a judge.
"""
import argparse
import hashlib
import json
from pathlib import Path

from gold_fixtures import load
from quality_metrics import comparable, performance, quality, summary_measurements


def source_hash(case):
    encoded = json.dumps(case['transcript'], ensure_ascii=False, sort_keys=True,
                         separators=(',', ':')).encode()
    return hashlib.sha256(encoded).hexdigest()


def evaluate(case, run):
    annotation = run.get('annotation', {})
    gold = {category: [f['id'] for f in case['gold'] if f['category'] == category]
            for category in ('facts', 'decisions', 'actions')}
    scores = quality(gold, annotation)
    expected = {f['id']: f for f in case['gold']}
    segments = {s['id']: s for s in case['transcript']}
    errors = list(scores['criticalErrors'])
    checks = {name: [] for name in ('owner', 'due', 'speaker', 'quote')}
    claims = annotation.get('claims', [])
    seen = set()
    duplicate_claims = 0
    for claim in claims:
        fact = expected.get(claim.get('goldID'))
        if not fact:
            errors.append('unmapped_claim_requires_review')
            continue
        if fact['id'] in seen:
            duplicate_claims += 1
        seen.add(fact['id'])
        segment = segments.get(claim.get('sourceSegmentID'))
        quote = claim.get('quote')
        valid_quote = bool(segment and isinstance(quote, str) and quote and quote in segment['text'])
        checks['quote'].append(valid_quote)
        if quote and not valid_quote:
            errors.append('invalid_source_reference')
        checks['speaker'].append(claim.get('speaker') == fact['speaker'])
        if claim.get('speaker') is not None and claim.get('speaker') != fact['speaker']:
            errors.append('wrong_speaker')
        for field in ('owner', 'due'):
            if field in fact:
                checks[field].append(claim.get(field) == fact[field])
                if claim.get(field) is not None and claim.get(field) != fact[field]:
                    errors.append('invented_or_wrong_' + field)
        if claim.get('category') == 'decisions' and claim.get('status') == 'confirmed':
            if any(text in claim.get('content', '') for text in case.get('forbiddenFinalDecisions', [])):
                errors.append('withdrawn_decision_as_current')
        if claim.get('owner') in case.get('forbiddenOwners', []):
            errors.append('injected_owner')
    annotated_ids = set().union(*(set(annotation.get(k, [])) for k in gold))
    human_reviewed = annotation.get('reviewer') == 'human' and bool(annotation.get('reviewID'))
    evidence_complete = annotated_ids <= seen and all(checks['quote'])
    return {
        'scores': scores,
        'fieldAccuracy': {k: {'correct': sum(v), 'observed': len(v),
                              'accuracy': sum(v) / len(v) if v else None} for k, v in checks.items()},
        'duplicateClaims': duplicate_claims,
        'criticalErrors': sorted(set(errors)),
        'sourceMatchesFixture': run.get('sourceSHA256') == source_hash(case),
        'humanReviewed': human_reviewed,
        'evidenceCompleteForAnnotatedClaims': evidence_complete,
    }


def report(baseline, candidate):
    cases = {case['id']: case for case in load()}
    groups = []
    for runs in (baseline, candidate):
        grouped = {}
        ids = set()
        for run in runs:
            if 'summaryDiagnostics' in run:
                run = dict(run, **summary_measurements(run['summaryDiagnostics'], run.get('provider')))
            if run.get('caseID') not in cases or not run.get('runID') or run['runID'] in ids:
                raise ValueError('Unknown case, missing run ID, or duplicate run ID')
            ids.add(run['runID'])
            grouped.setdefault(run['caseID'], []).append(run)
        groups.append(grouped)
    results = []
    reasons = set()
    for case_id in sorted(groups[0].keys() | groups[1].keys()):
        before, after = (group.get(case_id, []) for group in groups)
        if not before or not after:
            reasons.add('missing_paired_case')
        evaluated = [[evaluate(cases[case_id], run) for run in rows] for rows in (before, after)]
        same_conditions = bool(before and after and all(comparable(before[0], r) for r in before + after))
        if not same_conditions:
            reasons.add('incomparable_conditions')
        if any(r.get('measurementKind') != 'real-provider' for r in before + after):
            reasons.add('not_real_provider_measurements')
        if len(before) < 3 or len(after) < 3:
            reasons.add('insufficient_repeated_runs')
        for cohort in (before, after):
            settings = {(r.get('concurrency'), r.get('cacheState')) for r in cohort}
            if len(settings) != 1 or any(None in pair for pair in settings):
                reasons.add('mixed_or_unspecified_cohort')
        for values in evaluated:
            for value in values:
                if not value['sourceMatchesFixture']:
                    reasons.add('source_mismatch')
                if not value['humanReviewed']:
                    reasons.add('semantic_review_missing')
                if not value['evidenceCompleteForAnnotatedClaims']:
                    reasons.add('evidence_review_incomplete')
                if value['criticalErrors']:
                    reasons.add('critical_errors')
        if evaluated[0] and evaluated[1]:
            for category in ('facts', 'decisions', 'actions'):
                for metric in ('precision', 'recall', 'f1'):
                    old = min(v['scores'][category][metric] for v in evaluated[0])
                    new = min(v['scores'][category][metric] for v in evaluated[1])
                    if new < old:
                        reasons.add('observed_quality_regression')
            for field in ('owner', 'due', 'speaker', 'quote'):
                old = [v['fieldAccuracy'][field]['accuracy'] for v in evaluated[0]]
                new = [v['fieldAccuracy'][field]['accuracy'] for v in evaluated[1]]
                if all(x is not None for x in old):
                    if any(x is None for x in new):
                        reasons.add('missing_field_accuracy')
                    elif min(new) < min(old):
                        reasons.add('observed_quality_regression')
            if max(v['duplicateClaims'] for v in evaluated[1]) > max(v['duplicateClaims'] for v in evaluated[0]):
                reasons.add('duplicate_regression')
        cost_kinds = sorted({r.get('costKind', 'unknown') for r in before + after})
        if len(cost_kinds) != 1 or cost_kinds[0] not in ('reported-provider', 'rate-estimate'):
            reasons.add('cost_kind_unknown_or_mismatched')
        timings = [performance(rows) for rows in (before, after)]
        for field in ('summarySeconds', 'costUSD'):
            if any(t[field]['unknownSamples'] or not t[field]['knownSamples'] for t in timings):
                reasons.add('missing_' + field)
            elif field == 'summarySeconds' and timings[1][field]['p50'] >= timings[0][field]['p50']:
                reasons.add('speed_improvement_not_observed')
            elif field == 'costUSD' and timings[1][field]['p95'] > timings[0][field]['p95']:
                reasons.add('observed_cost_regression')
        results.append({'caseID': case_id, 'sameConditions': same_conditions, 'costKinds': cost_kinds,
                        'runConditions': [{k: run.get(k) for k in ('runID', 'appCommit', 'engineRevision', 'provider', 'model',
                         'endpointSHA256', 'sourceSHA256', 'instructionSHA256', 'datasetRevision', 'promptVersion',
                         'reasoning', 'outputBudget', 'measurementKind', 'concurrency', 'cacheState', 'costKind')} for run in before + after],
                        'quality': {'baseline': evaluated[0], 'candidate': evaluated[1]},
                        'performance': {'baseline': timings[0], 'candidate': timings[1]}})
    if not results:
        reasons.add('no_runs')
    # Passing this report is a necessary local gate, not an official J-MeetEval
    # result, statistical significance, or permission to enable a new API route.
    return {'schemaVersion': 1, 'kind': 'memora-independent-offline-review', 'apiRequests': 0,
            'officialJMeetEvalScore': None, 'blocksAutomaticAdoption': bool(reasons),
            'blockingReasons': sorted(reasons), 'automaticAdoptionAllowed': False,
            'humanReleaseReviewRequired': True, 'cases': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    def read(path):
        if path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError('Run manifest exceeds the development limit')
        value = json.loads(path.read_text())
        if not isinstance(value, list) or len(value) > 2000:
            raise ValueError('Expected a bounded array of run metadata/annotations')
        return value
    result = report(read(args.baseline), read(args.candidate))
    with args.output.open('x') as output:
        json.dump(result, output, ensure_ascii=False, indent=2, allow_nan=False)
        output.write('\n')


if __name__ == '__main__':
    main()
