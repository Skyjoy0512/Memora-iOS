# Native Liquid Glass header — 2026-10-23/24

Bounded follow-up to the selected create/search/toolbar controls. This does not
complete the outstanding Memora 1.0 phases or add proprietary recorder support.

## Changes

- Top-right create uses native SwiftUI `Menu`, not a custom popover, navigation
  zoom or timed dismissal. Empty-Library capture requests reuse the same actions
  in a native confirmation dialog. Recording, scoped audio import, memo, online
  meeting, new chat and the feature-flagged calling action retain their paths.
- Record-detail play/share use native `ToolbarItemGroup`; remove the delayed
  icon substitution, offset/reveal and disabled-hit-testing sequence. The actual
  record navigation zoom, playback implementation, sharing and More actions stay.
- Search moves to the sidebar, naming the current Library/Journal/Ask AI/Tools
  destination. Reuse each screen's existing search and hide the composer during
  Library/Journal search. Secondary People/Documents search is unchanged.
- Library and Journal show device status in the former search position, opening
  the existing recorder hub. A remembered device is not a live connection.
- Omi reads the optional standard Bluetooth Battery Service (180F), Battery
  Level characteristic (2A19), with read/notification capability checks. Validate
  exactly one byte in 0...100; clear readings on disconnect/new connection/error.
  Reject callbacks from another peripheral and abandoned connection attempts.
  Missing battery data stays unknown, never the phone's battery or sample data.
  PLAUD/other vendors remain audio-import paths, not newly paired devices.

The system owns menu material and presentation, following
[Apple's standard-control guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
The optional battery interpretation follows the
[Bluetooth Battery Service specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/BAS_v1.1/out/en/index-en.html).
No permission strings, OAuth scopes, deployment target, account or project
configuration changed. No real recording, send, account login or paid API call.

## Build and host verification

- Debug preview succeeded: `2026-10-23T23-51-59-c8ca2a8d.log`.
- Release simulator build succeeded: `2026-10-23T23-54-45-168a0abe.log`.
- Both retain 11 existing warnings. Debug log confirms iPhoneSimulator27.1.sdk;
  deployment remains iOS 26. The preview is updated through `bitrig preview`.
- Full host runner: 5/5 suites passed (next-generation, design-refresh,
  background-summary, composer-layout, optimization). Artifacts, including
  copied final build logs:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-native-header-20261023-quality`.
- New host checks execute production `RecorderBatteryState` across all 256 byte
  values, nil/empty/multi-byte data, zero/full charge, identity, reconnect and
  disconnect. These test parsing/ownership, not CoreBluetooth hardware callbacks.
- Design-refresh suite rerun after updating AGENTS/DESIGN also passed. Structural
  contracts supplement UI checks; they are not runtime/device evidence.
  An earlier motion check still required the removed custom capture zoom and
  failed; update that contract to require native Menu/dialog, not bypass the gate.

## UI verification

Final UI run: **8/8 passed**, failed/skipped/flaky/interrupted all zero, retries
zero. Run `01a1694a-8c5f-794d-9291-b1106ded9d35`; report
`.e2e/regression/native-header-verified/report.json`. 93 discovered / 8 selected /
85 filtered out; the other 85 were not executed or counted as passes. Model
tokens/calls and downloads are zero. Summary: `validation-summary.json`.
Checks cover native create → audio picker cancel → reopen → memo in Light/Dark,
real recorder hub access, Library/Journal/Ask AI/Tools sidebar search, query
clear/project isolation, actual saved-source search, existing chat actions and
the empty-Library native-dialog route. They do not exercise real BLE hardware.
Dedicated UI tests reinstall only their own test simulator app, not the user's
Bitrig preview. Credentials are removed from the test process, telemetry disabled,
and tests use exact locators without model/agent calls or live provider requests.

Earlier unsuccessful runs remain separately recorded:

- `native-header-initial`: 7 selected, 6 passed / 1 failed. Search fill raced the
  incoming field. The shared helper now waits for stable bounds and focuses it.
- `native-header-final`: 8 selected, 6 passed / 2 failed. The old search test
  expected “記録を検索” instead of the existing “ファイルを検索”. The new Ask AI test
  tried Done while native search was editing; leave native search mode first,
  then close the actual sheet. Neither failure is counted as a successful run.

Built-in preview: visually checked create Light/Dark, native record toolbar,
Reduce Motion Menu open/dismiss, and largest accessibility text. At largest
size the native Menu scrolls; a drag inside it reached the final new-chat action.
A first AX-container scroll dismissed the Menu instead and was not counted as
proof of reachability. Restore Light / large / Reduce Motion off afterward.

## Screenshots and boundaries

- [Library header Light](library-header-light.png), [Dark](library-header-dark.png).
- [Search in the sidebar](sidebar-search-light.png),
  [Library search](library-search-dark.png), [Journal search](journal-search-light.png).
- [Native create Menu](create-menu-light.png).
- [Dark / Reduce Motion](create-menu-reduce-motion-dark.png).
- [Largest text header](library-accessibility-dark.png).
- [Largest text Menu](create-menu-accessibility-dark.png),
  [scrolled to the final action](create-menu-accessibility-bottom-dark.png).
- [Immediate native record toolbar](record-toolbar-light.png).

These are actual after-state captures. The recovered recording shown in preview
already had a processing failure; retry/playback was not invoked in this check.
Header/search captures come from the dedicated test simulator; the others use
the built-in preview. All linked captures were visually reviewed.
No matched before/after animation capture was made. Screenshots prove layouts
and end states, not frame timing, responsiveness, energy or a measured speedup.

Real BLE connection/battery notifications, physical recorder firmware, real
audio import/recording, spoken VoiceOver, Japanese marked-text composition,
all screen sizes and real-device animations remain unverified. No fabricated
connected/battery screenshots or percentage improvement is reported. Existing
SQLite, workspace/privacy, approvals and attachment/composer implementations
were not replaced. The other unselected UI regressions remain unexecuted here.
