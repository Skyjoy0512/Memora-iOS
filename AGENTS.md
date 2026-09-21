# AGENTS.md — Memora

SwiftUI app for iPhone (iOS 18 deployment target, built against the iOS 27 SDK).
App sources live in `App/`, configuration in `Project.json`, design notes in
`DESIGN.md` and `MCP.md`.

## Working agreement

- Change the UI, layout, or copy only when the request asks for it. Otherwise
  optimise and refactor code without altering what is on screen.
- Build after every change and keep the working tree committed.
- Records live in the SQLite store (`App/LocalStore.swift`); only settings belong
  in `UserDefaults`. Audio and photos are files under the app container, referenced
  from a record by name (`App/MediaFiles.swift`); never inline the bytes again.
- One type per file; comments explain why, not what; prefer `var` for stored
  properties in structs; no `#Preview` or `PreviewProvider`.

## Known regressions to avoid

- **Tab bar** (`App/ProminentTabBar.swift`): the bottom tabs must stay a
  `UISegmentedControl`. It is what draws and animates the system's Liquid Glass
  selection bubble. Do not swap it for a SwiftUI segmented control and do not set
  `allowsHitTesting(false)` on it — either change makes the selection jump to the
  new tab instead of morphing across.
- **Files screen top chrome**: do not drive the navigation bar's visibility from
  a scroll-offset flag. Hiding and showing the bar from that state re-runs
  layout, which is read back as more scrolling and freezes the screen. The
  section switch belongs inside the scroll content so it scrolls away instead.
- **Journal (Home)**: the tab's own `ScrollView`/`List` must stay the screen's
  primary scroll view, so the large title and search bar collapse the way the
  system expects.

## Known gaps (not bugs to fix silently)

- Cloud storage, MCP, Google Drive, on-device Whisper and local LLM are
  preferences only; the services behind them are not implemented. The app says
  so rather than returning sample results.
- Recording, transcription and summarization never fill in sample content: when
  no engine can run, the record keeps its audio and shows the failure with a
  retry.
- Text being edited inline keeps a draft (`DraftStore`), restored next time that editor opens.
- A recording in progress keeps a draft; if the app stops, the audio is recovered
  as its own record and is never re-recorded automatically. Voice input is
  refused (with a reason) while a recording owns the audio session.
- Sign-in and purchase are not connected: the screens say so, and no local
  account or subscription flag is set from them. `MemoraAccount` and
  `startSubscription()` stay in the model for a later phase.
- The Ask AI fallback never invents answers; when no engine can run it says so.
- The composer shows the real AI engine (`AIEngine`), not a separate model label.
- Backlog and phase status live in `docs/IMPROVEMENT_BACKLOG.md` and
  `docs/OPENCODE_IMPLEMENTATION.md`.
