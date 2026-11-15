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
Native iOS measured save boundaries are still required for the full adoption
comparison. The host runner below executes the seven orchestration variants.
`summary_report.py` refuses
automatic adoption of these raw measurements. This is a safe limited-evaluation
runner, not completion evidence for Level 3 or native app performance goals.
Neither Level 2 nor Level 3 was executed in this change.

## Native orchestration and streaming runner

`native_runner.py` executes the production `MeetingSummarizer`, planner, scheduler,
cache, CloudAIService, URLSession/SSE decoder, parser and LocalStore in a macOS
host executable. No app dependency or UI is added. Build it into a new external
location with `bash tools/evaluation/build-native.sh /external/new-driver`.
The accompanying `.build.json` binds the binary to a before/after source snapshot.
Compilation or execution during a source revision invalidates the result.

The manifest example factory `tests/test_native_runner.py:manifest(driver)`
defines the full schema, including synthetic source metadata, preferences,
transcript UUIDs, exact model/provider/endpoint, reviewed billing limits, code and
driver hashes. `integration()` shows all seven runs. Replace the synthetic source
only with explicitly approved evaluation data and recompute its canonical digest.
Optional `source.template` uses the existing SummaryTemplateChoice codec, so
custom formats remain explicit. All runs in one manifest share the same complete
source, preferences, model, prompt revision and billing contract. Run order and
repetitions are explicit in `runs`; never treat one repetition as significance.

```sh
python3 tools/evaluation/native_runner.py --driver /external/new-driver \
  --manifest /external/reviewed-native-manifest.json --output /external/new-native-plan.json
```

This default command is offline, has zero API requests and does not read a key.
Execution requires `--execute --grant /external/native-grant.json`, a new output
directory, the exact-manifest/source/endpoint/expiry grant and the same dedicated
evaluation key/external enforced cap as the raw runner. Do not execute without
the independently established provider-prepaid/billing-proxy guard. No live
evaluation or billing setup was performed here.

Every dynamic request, including warmup, hierarchical merge and continuation,
passes a shared request/token/worst-rate USD ledger and rechecks the grant before
transmission. The original output ceiling and reasoning settings are unchanged.
When a provider request has no explicit output field, a separately reviewed
`implicitOutputCeiling` including reasoning is mandatory for reservation only;
the broker never inserts it into the real body. Unknown ceilings/prices are
refused. The driver receives a placeholder credential and a minimal environment;
all URLSession requests are intercepted by a fail-closed URLProtocol. Only the
broker child holds the evaluation key and may send to the granted HTTPS endpoint.
Raw SSE bytes pass through without waiting for the full body. Redirects, request
overflow, 429, expiry and deadlines stop new work without retries or paid fallback.
Warm-cache setup is a separate recorded phase whose requests consume the same
limits. Cancellation terminates the corresponding broker network process.

The seven labels are `single-pass` (original UUID source), `capacity-single-pass`
(current compact source/capacity policy), `hierarchical` (serial),
`parallel-hierarchical`, `sot`, `cache-cold`, `cache-warm`. Hierarchical comparisons
require the same explicit `partCapacity` and matching model/output settings;
the artificial cap can only reduce the production capacity. A single-source
route that does not fit, or a hierarchical route with only one part, fails before
inference instead of silently changing its label. The capacity variant currently
retains UTF-8 conservative token planning; it is not a model-tokenizer benchmark.
SoT and width 3/4 can be selected only in this development compiler configuration;
this never installs a production gate approval or guesses an account limit.

`runs.jsonl` retains generated summaries, numeric app diagnostics, actual route
part counts and separate warmup/measured phases. `matrix.json` groups by variant,
width and phase, reports successful P50/P95/maximum plus failures separately,
and keeps missing cost/quality/device measurements unknown. Source-invalid runs
are explicitly invalidated at collection level. Host streaming and broker IPC
timings are **not iOS device performance**. Persistence is labelled
`host-summary-document`: it measures a real SQLite write/readback of the generated
result, not MemoraModel's full iOS record/task/history transaction. Peak device
memory, battery, thermal and independent semantic scores remain unmeasured.
`automaticAdoption` is always false; an independently reviewed real iOS comparison
is still required before enabling SoT. The free CI checks seven variants/eight
phases, fragmented SSE, warm reuse, source guards, budget/permission/429/timeout
failure paths with mock inference only.
