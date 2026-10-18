# Remaining validation follow-up

## Changes

- Calendar cell width/height scale only for accessibility Dynamic Type categories. Ordinary 52×80pt geometry, typography, padding, selection glass ID and morphing remain unchanged. Text size changes keep the selected date visible without an added animation.
- AutoLocationLogger explicitly handles authorizedAlways in its authorization switch and removes two unnecessary awaits within the main actor. Permissions and the monitoring behavior are unchanged.
- Debug-only RecordStore failure injection uses a Mutex (available from iOS 18, verified in the installed iOS 27 SDK) so the sync and async persistence queues consume its one-shot flag safely. Release persistence code and SQLite schema are unchanged.
- Notification task-ID decoding is shared with its regression check. Existing resident notice routing, notification payload, timing, permission requests and task navigation are unchanged.

## Automatic checks

RecordStoreFailureChecks compiles the production RecordStore in Swift 6 complete concurrency checking with an isolated in-memory backend; it never opens the app database. It checks failed async commits leave the previous record/draft intact, concurrent requests consume exactly one injected failure, and later sync commits recover. It does not prove SQLite disk transactions; existing in-app Store failure injection / Atomic commit checks cover that implementation.

TaskReminderChecks checks notification IDs, valid/invalid payloads, preservation of the due day, custom reminder time and default 9:00. It does not simulate OS delivery or tapping a notification. RootNavigationChecks continues checking tab/route/scope boundaries.

The main target has no AppIntents dependency; the widget extension has its own OpenMemoraIntent. The metadata extraction warning is left visible rather than changing project settings or adding an unused App Intents dependency.

## Operational boundaries

Simulator/device interaction results are reported in the completion message. Accessibility test settings must be restored in a finally block; temporary large-text testing must not leave the user's simulator enlarged.

Real-device recording/background audio, external recorders, configured external AI, real online meeting recording and real team sharing still require hardware/service access. Notification scheduling and payload checks are separate from actual delivery and tapping. External deep-link launch is separate from route checks. No samples or fabricated successful results are added.

## Results from this follow-up

- Debug build succeeded with only the existing App Intents metadata warning. The four code warnings were removed.
- RecordStoreFailureChecks, TaskReminderChecks and RootNavigationChecks passed.
- iPhone 18 Pro Max: accessibility_extra_large showed full selected weekday/date and kept the selected day centered. The normal-size calendar was checked after restoring `large`.
- VoiceOver enabled: full selected-date label, three tab names/selection states, composer and FAB labels were present in the accessibility tree. VoiceOver was then disabled. This is label/state verification, not a complete spoken-feedback or gesture audit.
- Changing to iPhone 17e made the built-in simulator inactive (its inventory became empty). That device's app layout could not be inspected; the target was changed back to iPhone 18 Pro Max. Small-device validation remains blocked by the simulator state.
- The automated checks do not exercise OS notification delivery or external deep-link launch. The additional live checks below cover those entry points separately.

## Live entry-point checks — 2026-10-12

Tested on the built-in iPhone 18 Pro Max simulator with ordinary text size. No application UI, typography, navigation, persistence, or project configuration was changed for these checks.

- External record Deep Link: copied the existing 通話 record's link from its detail menu, pasted it into Safari, accepted the system “open in Memora” prompt, and observed that exact record's detail. The composer showed `「通話」に質問`. Returning to the file list restored `Memoraに質問` and the original two records remained present. This checks an actual external launch, not just the pure route helper.
- Local task notification: created a temporary own task `QAReminder２０２６１０１２`, due October 12, with a 17:40 reminder. Granted the native notification permission when requested. Left Memora displaying the Library file list and backgrounded it. The OS delivered the expected task title and `今日が期限です。` at 17:40.
- Opening that delivered notification from Notification Center switched to Journal → Tasks and presented the existing TaskEditView with the exact temporary task title. The simulator's initial notification activation exposed the native “open” action; the standard full right swipe opened the notification. No notification callback was injected or faked.
- Cancelled the editor and deleted only the temporary task through its existing context menu. The deletion confirmation and the original Meeting confirmation / 改訂見積書の送付 tasks were observed afterward. The new test task is no longer active; no original task was edited. Notification permission remains allowed on this simulator.

## Terminated-app notification check — 2026-10-12

- Created a separate temporary own task `QAColdStart`, due October 12, with a 17:51 reminder. Confirmed the final 17:51 value before saving. Closed Memora by swiping its card away in the app switcher; observed that only Safari's card remained, then returned to the system Home screen.
- The OS delivered `QAColdStart` / `今日が期限です。` at 17:51 while Memora was closed. Opened the delivered notification with the standard full right swipe in Notification Center. After the launch completed, Journal → Tasks and the existing TaskEditView showed the exact saved task. This exercised the real persisted-task load and notification callback after a user-initiated termination.
- Cancelled the editor and deleted only `QAColdStart` through its context menu. Confirmed its deletion message and the original two open tasks afterward. The font size and application layout were unchanged.
- Tried iPhone 17 as a different, narrower device after the earlier 17e problem. `bitrig build -destination selected` succeeded (the existing App Intents warning only), and the simulator inventory reported iPhone 17 as running. Nevertheless, the observation API returned `simulator device is not booted`, including after a ten-second startup wait. No iPhone 17 screen was observed; this does not establish an app layout failure. Returned the target to iPhone 18 Pro Max.

Still unverified: external `memora://task/<UUID>` launch, complete VoiceOver spoken/gesture behavior, and small-device layout (the simulator boot issue above). The current task UI exposes no task-ID/link-copy action; code inspection confirms the existing URL handler validates a stored task ID and calls the same `openTask` route, but this is not an external-launch result. No diagnostic UI or logging of private task IDs was added just to enable this check.

Real-device background/lock-screen recording, actual audio-file import, external recorders, real online meeting recording, configured external AI answers and live team sharing also remain pending. A simulator notification result does not establish real-device delivery behavior.

## Background summaries — 2026-10-18

- A summary started in the summary sheet now writes a `PendingSummaryJob` with its
  template, engine, model, preferences and consent to SQLite. `BGProcessingTask`
  (`app.memora.summaries.processing`) is registered at launch, queued when the app
  goes to the background, and re-queued at launch if a job survived a stop.
- A cloud job requests network connectivity; an on-device job does not. An
  expired window cancels the run, returns the record to `waitingForSummary`, and
  keeps the job for the next window. The record and its fingerprint checks are
  the same ones the foreground path uses.
- iOS chooses when a processing window runs, and a force-quit app is not
  relaunched. The simulator does not force a `BGProcessingTask`, so actual
  scheduling, termination, battery and network conditions still need a device
  check. No external AI call was made for this validation.
- `tools/checks/run-background-summary-job-checks.sh` verifies the project's
  permitted identifier / `processing` background mode and the job's Codable
  round-trip.

Foreground return is a second safety net: if iOS did not run the processing window,
`resumePendingSummariesIfNeeded()` continues the same queued job when the app becomes
active. The record's summary card says that the work is continuing in the background
and offers "いま要約する" to run the normal foreground sheet instead.
