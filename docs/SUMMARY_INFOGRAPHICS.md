# Content-led summary infographics — 2026-10-25

## Behavior

- A separate, versioned interpretation replaces source-order transcription **after explicit generation**. The model selects up to four metric, flow, comparison, timeline or note panels, each containing at most two short claims. Display fields prohibit embedded newlines so arbitrary line breaks cannot create an oversized bitmap. The original summary is never rewritten by this action.
- Inline presentation contains only the image. The requested heading, enlarge/share row, caption and regenerate button are removed. Long-press and VoiceOver actions retain enlargement, sharing and generation. The full-text sheet exposes diagram claims, source quotations, model provenance and the untouched summary.
- Opening a record/menu/generation sheet sends nothing. Confirming generation captures the current model, checks the record policy or a one-run explicit cloud consent, and discloses possible cost. Closing cancels. There are no tool calls, external searches, automatic retries or continuations in this generator.
- Every claim requires a matching quotation from the saved summary. Structural bounds, unique identities, numeric tokens and source matches are checked before persistence. These checks **cannot prove semantic correctness** (including units, causal inference or factual accuracy of the original summary). AI interpretations remain labeled and inspectable, not verified facts.
- SQLite stores a bounded JSON document on the existing Meeting record; PNG bytes are not in the database or UserDefaults. Legacy records decode without it. A damaged optional field cannot prevent record recovery. Failed generation/save keeps the old artifact; edited summaries/privacy invalidate its display. Workspace, restore/protection, cancellation and concurrent changes are rechecked before publication by the existing atomic writer.
- Three bottom questions use the valid diagram's questions, otherwise local summary-derived prompts. Selection stages an editable **record-scoped** draft, never sends or approves an operation. Existing draft, attachment, mentions or an in-flight chat take precedence. Sources and active detail scope are rechecked at selection; normal send-time privacy checks remain.
- Only the exact, unedited fictional diagnostics sample has a hand-authored display fixture. Its image says `表示サンプル（AI生成は未実行）`; no real recording is substituted or billed.

## Verification

Environment: Apple Silicon Mac, macOS 27.0.1, Swift 6.4, iOS 27.1 SDK; iOS 26 deployment target. No project configuration or dependencies changed.

| Check | Result / boundary |
| --- | --- |
| `bitrig preview -platform iOS` | Passed, 11 existing deprecation/metadata warnings; latest chrome removal is in preview |
| `run-summary-reading-checks.sh` | Passed, including new infographic checks; existing prompt, transcript, source excerpt, access, editing, relations and SQLite failure/reopen checks |
| `run-infographic-checks.sh` | Passed: production generator, validator, snapshot, domain staging and atomic writer; mocked engine, real isolated SQLite; invalid JSON/evidence/numbers/IDs, consent, save failure, privacy/workspace races and draft/attachment/mention guards |
| `run-audio-import-checks.sh` | Passed: production Meeting codec including new optional-field round trip, legacy absence and malformed-field recovery; import/restore regression checks |
| `run-cloud-session-checks.sh` | Passed: production provider transport and agent/session regressions using URLSession fixtures; no network, credentials or paid calls |
| `run-background-summary-job-checks.sh` | Passed: production queue/cancellation/atomic save, mocked OS/model |
| UI E2E | **2 passed / 1 failed** in final full run `01a1705e-eeb2-7916-95c7-0793fc7ccdcb`; dedicated fresh simulator, no real provider calls. New infographic/questions and adaptive/task scenarios passed. Legacy summary-reading failed Japanese text entry; not all-green |

The first UI run was intentionally interrupted when the user requested additional chrome removal (one passed, one interrupted, one skipped); it is not counted as a successful complete run. The final run uses the updated long-press path.

Intermediate run `01a17055-03af-72c1-9893-41308623976d` passed the adaptive and infographic scenarios but failed the legacy summary-reading scenario: Japanese text replacement returned an unexpected trailing `だ`. The test now positively waits for the original text and focus and checks the exact replacement before saving. The next run passed that replacement/save but failed opening the image menu while the scroll view was still moving (trace scroll value 18% → 14%). Long-press now uses the existing stable-bounds wait, matching other native control interactions. Neither intermediate run is reported as an all-green suite, and no product IME fix is claimed.

Run `01a1705e-eeb2-7916-95c7-0793fc7ccdcb` again passed both new-feature scenarios, but the fast Japanese `fill()` replacement again returned a trailing `だ`. Focus alone did not resolve it. A separate experiment (`01a17064-e483-75d4-9067-57652fd5897b`) explicitly cleared before sequential typing: `clear()` itself failed with expected empty / observed `だ`, so sequential typing was never reached. That unsuccessful experiment was removed; the committed regression retains exact-value assertions and the failing `fill()` path, without skipping or relaxing the check. After three occurrences of the same residual-character symptom, retries stopped. App-versus-input-driver cause is **not established**; no product IME fix is claimed. Later edit/export/reopen steps after the failure were not executed successfully in the final run.

Manual Bitrig simulator inspection: fictional sample's inline infographic, removal of all four requested chrome elements, native long-press menu, enlarged image and all three bottom questions. Light and Dark question rendering visually inspected; Light restored. Sample PNG observed at 1440 × 1983 pixels. This is an output size, not a performance measurement.

### Screenshots

- [Before](summary-infographic-before.png): previous source-ordered excerpt with action row.
- [After](summary-infographic-after.png): clean inline diagram, scrolled to the image.
- [Full diagram](summary-infographic-full.png): enlarged sample with content-selected panels.
- [Bottom questions](summary-questions-after.png): three visible record-specific prompts.

Screenshots have different scroll positions; they are visual evidence, not pixel-diff or performance baselines.

## Not verified / remaining

- **P0 before a release sign-off:** investigate Japanese edit replacement/deletion (`だ` remains). The existing summary-reading E2E is still failing; a successful build/new-feature test is not a complete regression pass. Reproduce with ordinary human/IME editing and isolate the automation driver before changing editor behavior. No record in the user's preview was edited during these tests.
- Real-provider interpretation quality and format adherence, Apple Intelligence generation on supported hardware, and actual cloud cost require a separately authorized provider/device run. No API credentials were accessed or requests sent during this work.
- Real-device background BYOK execution remains unverified; transport/queue regression success is not proof that iOS will keep an actual request running indefinitely.
- Dynamic Type extremes and VoiceOver gestures for the new menu/questions were not exercised on-device; controls use system text styles and 44pt minimum targets, and an accessible text/evidence alternative remains.
- No latency, energy or memory improvement is claimed; no before/after performance measurement was performed.
