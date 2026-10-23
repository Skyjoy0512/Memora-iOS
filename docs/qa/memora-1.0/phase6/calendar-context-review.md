# Calendar read lifecycle — 2026-10-24

This bounded Phase 6 follow-up changes internal authorization, not UI/layout,
stored records, calendar write behavior, OAuth scopes or project configuration.

## Reproduced and fixed

A new test through production `readCalendarTool` reproduced an accepted stale
result after `aiChatRequestID` changed during a suspended calendar read:
`Stale calendar result accepted: device / read / new request`.
The red run failed with a precondition trap (exit 133), not a passing check.

- Reuse `AgentConversationExecutionContext` rather than duplicate its request,
  thinking-message, workspace-generation and selected-policy checks. A calendar
  context also fixes the calendar revision before approval and revalidates live
  calendar access, integration enablement, registry/schema, person scope and
  Gmail/MCP result authorization at the existing suspension boundaries.
- Start the existing EventKit observation before approval, without reading event
  contents. Approval still precedes a cloud calendar fetch. Existing root
  notification/activation invalidation remains. Apple's
  [change-notification guidance](https://developer.apple.com/documentation/eventkit/updating-with-notifications)
  is the notification contract, not proof that a physical device delivered one.
- Refuse stale results without retaining their snapshot or returning event
  titles. A callback no longer owning the live message does not update its trace
  or blocked-tool state. An invalid read still owned by that request settles as
  failed and is not silently retried in that answer.
- A changed calendar ON/OFF preference invalidates the existing revision
  synchronously. OFF→ON cannot revive a prior preview, model-send authorization
  or artifact source. A no-op setting preserves a valid grant. A new approved
  request works and gets fresh transient IDs.

The protected-resource guidance was used to keep OS calendar permission and
AI-use approval separate. No new permission request or purpose string was added.

## Production-code host checks

`bash tools/checks/run-artifact-provenance-checks.sh --calendar-interface`

| Suspended boundary | Changes | Expected result |
| --- | ---: | --- |
| Cloud approval | 18 | No calendar fetch and no retained event snapshot |
| Cloud read | 18 | In-flight fixture read discarded; no returned event titles |
| On-device read | 18 | Same refusal, without adding a cloud approval requirement |

The 18 independent mutations cover request replacement/stop, workspace ABA,
message replacement/settlement/removal, restoring/protected store, calendar
revision change, integration OFF/OFF→ON, OS denied/unknown access, policy removal,
registry disable, plugin refusal, and revoked Gmail/MCP results.

Recovery checks exercise no-op settings, OFF→ON invalidation of preview/cloud/
artifact use, and a new read/approval with fresh IDs in both cloud/device modes.
The existing suite still checks refusal, cancellation, stable repeated-occurrence
IDs, empty/invalid/bounded sources, streaming schema, reference resolution and
approval data-change semantics. It never fetches real EventKit events or calls
a model/network provider.

Conversation state/EventKit responses/registry assembly are fixtures; the domain
tool, shared execution context, approval waiter, production registry and permission
logic run. The Gmail/MCP/Notion-only fixture models fail fast if the unrelated
calendar invalidation entry is called; they do not pretend to exercise Calendar.

Intermediate unsuccessful gates are preserved separately:

- The first recovery-test helper assumed a global read count of zero when a
  fresh message had no snapshot. A new request after a prior read correctly has
  a nonzero count. Compare the count captured immediately before approval
  instead, strengthening the no-fetch-before-approval assertion.
- The first full host run (`memora-phase6-calendar-context-20261024-quality`)
  failed next-generation because a fixture source changed while Swift was
  compiling it. The other four suites passed. It is not reported as a successful
  full run; the frozen-source rerun is recorded in the validation summary.
- The first UI run passed 5/5 on the earlier Debug build. The final observation-
  ordering change is small but is not covered by claiming that earlier run as a
  final-source test. A separate run repeats the selected UI checks.

## UI and build evidence

Final results/log identifiers are recorded in
`calendar-context-validation-summary.json`. Builds use Bitrig and the iOS 27.1
SDK with the iOS 26 deployment target retained. No Xcode test target was added;
host/UI results are not described as `bitrig test`/XCTest success.

- Final Debug preview succeeded: `2026-10-24T08-10-30-b3bfa0b3.log`.
- Final Release simulator build succeeded: `2026-10-24T08-11-29-081557d1.log`.
  Both report 11 existing warnings; no app source changed afterward.
- Frozen-source full host runner passed all five suites, exit 0. Logs and copied
  build logs are in
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase6-calendar-context-20261024-final-quality`.

The UI runner uses its own fresh dedicated simulator, exact locators, zero
retries and no model calls. The new test toggles only “Ask AIで利用する”, verifies
the disabled setting after restart, then re-enables it and confirms the device
permission action still exists. It never taps that permission action. Existing
approval/edit/SQLite save, decline/stop and header/search regressions are selected
separately; those do not prove the Calendar backend or an LLM integration.

Final Debug UI run: 5/5 passed, failed/skipped/flaky/interrupted all zero, retry
zero. Run `01a16b0a-6847-765e-99c0-346e2c08345c`,
`.e2e/regression/phase6-calendar-context-final/report.json`. 94 discovered / 5
selected / 89 filtered out and not executed. Model tokens/calls and downloads
are zero. All five execute the final application source.

Ordinary connector screenshots: [Light](calendar-unconfigured-light.png) and
[re-enabled, still unconfigured Dark](calendar-reenabled-unconfigured-dark.png).
Both were visually reviewed. They are not matched before/after UI comparisons,
an OS-permission dialog test or evidence of a connected/read calendar.

## Remaining boundaries

- Actual EventKit notification delivery, OS permission revocation/return,
  real calendar entries, live cloud/model requests and hardware remain untested.
- Calendar event creation and its OS-permission-await/save boundary need a
  separate write-path audit. This read fix is not a claim to have secured or
  tested every Calendar operation. Calendar-specific sharing settings are absent.
- No VoiceOver spoken operation, Japanese marked-text composition, frame timing,
  latency, energy or memory comparison was measured here. No numeric performance
  gain or matched before/after UI comparison is claimed.
- Settings screenshots are ordinary regression evidence, not a redesigned UI,
  real-calendar proof or a fabricated connected calendar. The broader Phase 6/7
  and public-release hardware checks remain unfinished.
