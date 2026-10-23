# Ask AI / sidebar / workspace / recorders — 2026-10-23

User-requested UI changes take precedence over the earlier blank-chat specification.
This is a bounded UI follow-up, not completion of all Memora 1.0 phases.

## Implementation

- Hide the guest sign-in footer in the drawer. Preserve account setup under
  Settings, signed-in account information, the plan action and the settings gear.
- Select one workspace from visible checked rows in Settings. Reuse
  `selectWorkspace`, team creation/joining and the real backend workspace list.
- Open the shared recorder hub from the drawer: Omi pairing/device details,
  PLAUD file import and generic recorder/voice-memo file import. Reuse the
  validated `importPickedAudio` / `LocalImportContext` / SQLite path, with picker
  cancellation, local failure feedback and a real save confirmation. No new
  proprietary device protocol or fabricated connection state.
- Show three flat agent-action suggestions in new chats. Derive bounded titles
  locally from real cloud-permitted personal records/tasks, excluding samples.
  Revalidate on selection; do not replace a draft/attachment or send a question.
  No model call, inferred memory, extra fee or persisted authorization is added.
  Without eligible data, show generic starting actions rather than pretend
  personalized results. Existing conversations/approval/composer paths remain.
- Keep the attachment control as a plain plus with a 44pt target. Replace the
  custom popover/navigation zoom/fixed 180ms delay with native SwiftUI `Menu`.
  All five photo/audio/file/mention/integration routes remain. The system owns
  the material and presentation, following [Apple's standard-control guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

## Verification

- Final Debug preview: `2026-10-23T23-17-46-88bceed5.log`, success, 11 existing warnings.
- Final Release simulator build: `2026-10-23T23-20-04-421daa7d.log`, success, 11 existing warnings.
  The Debug log confirms `iPhoneSimulator27.1.sdk`; deployment remains iOS 26.
- Full host runner: 5/5 suites passed, no skipped suites. Logs and copied build
  logs: `/Volumes/WorkspaceSSD/Development/Temp/memora-agent-ui-20261023-quality`.
- New host checks execute the production suggestion builder and model extension
  against a fixture model/store, with the production record privacy policy.
  They cover source changes/removal/revocation, tasks/completion, draft and
  attachment protection, samples, workspace/person scope, restore/protected
  store, title bounds and no auto-send. This is not a live SQLite/UI test.
- Built-in iPhone simulator: visually reviewed new chat and workspace Light/Dark,
  plain plus/native attachment menu, guest-free sidebar, largest accessibility
  text wrapping/scrolling and native Menu open/dismiss under Reduce Motion.
  A coordinate drag confirmed the final suggestion remains reachable at the
  largest size; an initial scroll on a non-scroll AX container had no effect.
  Restore simulator settings to Light / large / Reduce Motion off after checks.

- Final UI regression: **8/8 passed**, failed/skipped/flaky/interrupted all zero,
  retries zero. Run `01a16926-fbc9-76ab-9520-8d88c21048a5`, report
  `.e2e/regression/agent-entry-final/report.json`, 89 discovered / 8 selected /
  81 filtered out. The other 81 were not executed, not counted as passes.
  Covers proposal staging and draft restart, attachment routes and draft
  preservation, generic picker cancellation, workspace check/join sheet,
  account/plan access through Settings and existing chat/header/sidebar behavior.
- Initial runs are not counted as final passes: the first had 1 pass / 4 failures;
  the second had 4 passes / 4 failures. Fixed parent identifier propagation in
  the app, then corrected test routes/combined AX labels, file-picker Cancel
  localization, tapping an action row instead of empty space, and the native
  multiline XCTest bulk-fill suffix issue. The final test checks retained draft
  contents without bulk-replacing that multiline field. It does not claim to
  fix XCTest's fill operation or prove Japanese marked-text composition.
- The initial suggestion compile failed because lazy closures needed explicit
  `self`; corrected before the final Debug/Release/host/UI validations.

## Screenshots

- [Suggestions Light](suggestions-light.png), [Dark](suggestions-dark.png).
- [Largest text](suggestions-accessibility-light.png), [scrolled to final action](suggestions-accessibility-bottom-light.png).
- [Native attachment menu](attachment-menu-dark.png), [Reduce Motion](attachment-menu-reduce-motion-dark.png).
- [Menu with keyboard](attachment-menu-light.png), [staged draft](suggestion-draft-dark.png).
- [Workspace Light](workspace-light.png), [Dark](workspace-dark.png), [largest text](workspace-accessibility-dark.png).
- [Drawer without guest sign-in](sidebar-light.png).
- [Recorder hub](recorder-hub-light.png), [generic file import](recorder-import-light.png).

These are actual after-state screenshots, not generated mockups. Historical
before references remain in `docs/design-refresh/chat-surface/after/empty-light.png`
and `sidebar-light.png`; they were captured in an earlier session, not a matched
before/after measurement with identical data. All linked images were visually
reviewed. Recorder/import/menu-with-keyboard/draft captures come from the fresh,
dedicated UI test simulator; the other captures use Bitrig's built-in preview.

## Limits

- Omi hardware pairing/firmware, real recorder exports/USB providers and live
  microphone routes were not exercised. Other vendors' Bluetooth direct pairing
  remains explicitly unsupported. No actual account/OAuth scope or external
  service connection was changed.
- UI tests exercise the system file picker opening/cancellation; new generic
  recorder file save/failure UI has not been executed with a real file. Existing
  audio-import host regression checks cover storage validation/failure boundaries.
- Personalized eligibility is tested in host fixtures. The visual captures show
  generic suggestions because no eligible real record is present in that state.
- VoiceOver spoken operation, Japanese marked-text entry, actual provider/tool
  execution and real-device behavior remain separate checks. The native input
  implementation and approval paths were not replaced.
- No FPS/input-latency/memory/battery or animation-duration comparison was
  measured. Screenshots confirm layout/end states, not frame-perfect animation
  timing. Do not infer a numerical performance improvement.
