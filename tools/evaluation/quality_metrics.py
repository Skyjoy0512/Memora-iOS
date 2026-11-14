"""Deterministic gold-annotation and measured-run comparisons; no model or network."""
import math
import statistics


def precision_recall(expected, predicted):
    # IDs come from an independent reviewer/gold fixture, never an LLM self-grade.
    expected, predicted = set(expected), set(predicted)
    true_positive = len(expected & predicted)
    precision = true_positive / len(predicted) if predicted else (1.0 if not expected else 0.0)
    recall = true_positive / len(expected) if expected else 1.0
    return {'precision': precision, 'recall': recall,
            'f1': 2 * precision * recall / (precision + recall) if precision + recall else 0.0,
            'falsePositives': sorted(predicted - expected), 'missing': sorted(expected - predicted)}


def quality(gold, annotation):
    result = {name: precision_recall(gold.get(name, []), annotation.get(name, []))
              for name in ('facts', 'decisions', 'actions')}
    errors = list(annotation.get('criticalErrors', []))
    if any(result[name]['falsePositives'] for name in result):
        errors.append('unmapped_claim_requires_review')
    if annotation.get('unsupportedClaims'):
        errors.append('unsupported_claim')
    result['criticalErrors'] = sorted(set(errors))
    result['passesCriticalGate'] = not errors
    result['semanticReview'] = annotation.get('reviewer', 'notReviewed')
    return result


def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    # Nearest rank includes the actual tail; never interpolate away a slow run.
    return values[max(0, math.ceil(fraction * len(values)) - 1)]


def performance(runs):
    result = {'samples': len(runs)}
    for field in ('totalSeconds', 'transcriptionSeconds', 'summarySeconds', 'ttftSeconds',
                  'firstReasoningSeconds', 'bodyGenerationSeconds', 'inputTokens', 'outputTokens',
                  'reasoningTokens', 'cachedInputTokens', 'requests', 'costUSD', 'peakMemoryBytes',
                  'cacheWriteTokens', 'cacheHitRate', 'requestFailures', 'retries', 'tokensPerSecond',
                  'jsonParseSeconds', 'structuredParseSeconds', 'saveSeconds', 'cpuSeconds', 'mainThreadBusySeconds', 'batteryDelta', 'thermalState'):
        values = [r[field] for r in runs if isinstance(r.get(field), (int, float))
                  and not isinstance(r[field], bool) and math.isfinite(r[field]) and r[field] >= 0]
        result[field] = {'knownSamples': len(values), 'unknownSamples': len(runs) - len(values),
                         'p50': percentile(values, .5), 'p95': percentile(values, .95),
                         'maximum': max(values) if values else None}
    return result


def summary_measurements(diagnostic, provider):
    """Bridge app numeric exports without summing overlapping request latency."""
    count = diagnostic.get('requestCount')
    valid_count = isinstance(count, int) and not isinstance(count, bool) and count >= 0
    requests = diagnostic.get('requests', [])
    complete = (valid_count and isinstance(requests, list) and len(requests) == count
                and not diagnostic.get('measurementsIncomplete', True))
    def total(field):
        values = [r.get(field) for r in requests] if complete else []
        if not values or any(not isinstance(x, int) or isinstance(x, bool) or x < 0 for x in values):
            return None
        return sum(values)
    result = {k: total(k) for k in ('inputTokens', 'outputTokens', 'reasoningTokens',
                                   'cachedInputTokens', 'cacheWriteTokens')}
    result['requests'] = count if valid_count else None
    result['structuredParseSeconds'] = diagnostic.get('parseSeconds')
    result['saveSeconds'] = diagnostic.get('saveSeconds')
    outcomes = [r.get('outcome') for r in requests] if complete else []
    result['requestFailures'] = (sum(x == 'failed' for x in outcomes)
                                 if outcomes and all(x in ('completed', 'failed', 'cancelled') for x in outcomes) else None)
    input_tokens, cached = result['inputTokens'], result['cachedInputTokens']
    denominator = input_tokens
    if provider == 'anthropic':
        written = result['cacheWriteTokens']
        denominator = input_tokens + cached + written if all(x is not None for x in (input_tokens, cached, written)) else None
    if provider not in ('openAI', 'deepSeek', 'anthropic'):
        denominator = None
    result['cacheHitRate'] = (cached / denominator if denominator and cached is not None and 0 <= cached <= denominator else None)
    # Reasoning and visible token counts differ by API. Never divide aggregate
    # completion tokens by only the visible-text duration to invent a speed.
    return result


def comparable(before, after):
    # Cache/concurrency deliberately differ between cohorts; all quality knobs must match.
    fields = ('sourceSHA256', 'instructionSHA256', 'endpointSHA256', 'provider', 'model', 'reasoning', 'outputBudget',
              'datasetRevision', 'promptVersion', 'measurementKind')
    return all(before.get(f) is not None and before.get(f) == after.get(f) for f in fields)
