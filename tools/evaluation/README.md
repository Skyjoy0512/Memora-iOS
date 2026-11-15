# Development-only summary evaluation

No application data, BYOK credentials, network, model generation, or judge is
used by the offline commands. The app never imports this directory.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/checks/run-summary-evaluation-checks.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/evaluation/jmeeteval_offline.py --output /external/new-audit.json
PYTHONDONTWRITEBYTECODE=1 python3 tools/evaluation/summary_report.py \
  --baseline /external/baseline-runs.json --candidate /external/candidate-runs.json \
  --output /external/new-comparison.json
```

The comparison inputs are arrays of run objects with:

| Field | Meaning |
|---|---|
| caseID / runID | ID in `gold_fixtures.load()` / unique measurement ID |
| sourceSHA256 | `summary_report.source_hash(case)` of the complete synthetic transcript |
| instructionSHA256 | SHA256 of the actual explicit summary instruction |
| endpointSHA256 | Hash of the exact API endpoint; never include an API key |
| provider / model / reasoning / outputBudget | Actual unchanged generation settings |
| datasetRevision / promptVersion | Pinned input/instruction contract versions |
| appCommit / engineRevision | Different baseline/candidate code revisions, retained by the caller |
| measurementKind | `real-provider`, `mock`, or `host`; never relabel a simulation |
| concurrency / cacheState | Cohort conditions, kept separate by the caller |
| summarySeconds / transcriptionSeconds / totalSeconds | Separately measured wall-clock spans; null if unavailable |
| costUSD / costKind | Reported or explicitly estimated cost, or null / unknown |
| summaryDiagnostics | Optional numeric `SummaryDiagnostics.metricsJSON` object |
| annotation | Independent review of the actual generated output |

Each annotation has `facts`, `decisions`, `actions` arrays of gold fact IDs,
`reviewer: "human"`, an opaque `reviewID`, and observed `claims`. A claim uses
`goldID`, actual `sourceSegmentID`, `quote`, `speaker`, and optional `owner`,
`due`, `category`, `status`, `content`. Do not fill missing model evidence from
the gold fixture. Independent reviewers link paraphrases to gold IDs. Novel
claims not in the gold set require review; they are not automatically labelled
hallucinations. Confirmed unsupported claims go in `unsupportedClaims`.

The report checks quotes/IDs, known owner/due/speaker fields, withdrawn current
decisions and injection owners. Semantic review, readability, nuanced conditions
and facts outside the curated gold set require independent assessment. It does
not replace official J-MeetEval or statistical testing. Three repetitions per
cohort are only a minimum collection check, not proof of significance. A judge
alone cannot mark the report human reviewed.

App diagnostic imports preserve missing counters. Parallel request times are
not summed into summary time. Anthropic cache counters use their own denominator;
OpenAI/DeepSeek cache counts are subsets of reported input. No token throughput,
network-only latency, cost, or retry count is inferred without a measurement.
Estimated cost must remain labelled as estimated; an unknown BYOK price stays
null. A display timeline truncated at 256 events can still have complete numeric
request summaries; `measurementsIncomplete` is the relevant aggregate guard.

Unknown measurements, unreviewed semantics, mismatched settings/source, critical
errors, or insufficient repeated runs block automatic adoption. Even a passing
local report requires human release review and separate official evaluation.
No comparison results for real models have been generated in this work.

The official-rule runner needs the locked development environment; setup,
licenses, pins, and the deliberately unexecuted paid-evaluation boundary are in
`docs/JMEETEVAL_INTEGRATION.md`.

## Opt-in request runner (Level 2 building block)

`model_runner.py` accepts an explicit immutable request manifest. The unit-test
`manifest()` in `tests/test_model_runner.py` is a complete synthetic example.
`--manifest <file> --output <new-plan.json>` is a dry run: zero requests, no
credential reads. `--execute --grant <file> --output <new-directory>` additionally
requires a grant for the exact manifest digest, endpoints, source transmission,
expiry and an independent `MEMORA_EVALUATION_API_KEY`. A separately provisioned
prepaid account or billing proxy must enforce a hard cap no higher than the
approved limit. A client timeout/rate estimate is not that guarantee; without
an external spend guard do not execute. The grant is an operator attestation,
not a cryptographic verification of the provider's billing configuration.

The manifest declares total requests/tokens/USD/deadline, exact model/protocol,
source and actual request hashes, version IDs, reviewed context/framing/output
(including hidden reasoning) and maximum uncached rates. Unknown rates,
competing output caps, implicit multi-output/server-tool/media options, invalid
source hashes and insufficient budget are refused before a credential is read.
The live HTTP path is isolated in a process with an absolute deadline, refuses
redirects, bounds response bytes, and never retries 429/errors/truncation.
Reservations remain upper estimates, not measured usage or cost. In-flight
billing may remain unknown after a timeout. Retain the external hard cap.

Outputs are appended per actual attempted request; an existing output directory
is refused. Only error kinds/status/Retry-After are stored, not exception text.
Provider usage is preserved without filling missing counters. Reasoning time,
TTFT, app persistence, SQLite I/O, CPU/RAM/battery/thermal and total summary
latency are null when unobserved. Semantic annotations and judge scores are
never manufactured from the gold fixture or the generated answer.

This runner deliberately reports `raw-provider-request`, **not** the app's
`real-provider` pipeline timing. Variant/concurrency/cache labels identify the
exported request's origin, not proof that this runner executed that pipeline.
Native app cold/warm/SoT/hierarchy exports and measured save boundaries are still
required for the full seven-way adoption comparison. `summary_report.py` refuses
automatic adoption of these raw measurements. This is a safe limited-evaluation
runner, not completion evidence for Level 3 or native app performance goals.
Neither Level 2 nor Level 3 was executed in this change.
