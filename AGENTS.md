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
- `MemoraModel.swift` holds only stored state, loading and the derived indexes.
  Behaviour lives in `MemoraModel+<Domain>.swift` (Capture, Processing, Import,
  Meetings, Tasks, Journal, Trash, Media, Backup, Persistence, …); add new
  model code to the matching extension. Derived values that screens observe
  (aggregates, journal days, the samples flag) are assigned only when they
  change, so an unrelated edit does not redraw every screen reading them.
- In view bodies, compute a filtered or searched list once (`let` at the top of
  `body`) and pass it down; never re-derive it per row. Fast-ticking values
  (recording time, playback position) are read only in small leaf views.

## Known regressions to avoid

- **Tab bar** (`App/ProminentTabBar.swift`): the bottom tabs must stay a
  `UISegmentedControl`. It is what draws and animates the system's Liquid Glass
  selection bubble. Do not swap it for a SwiftUI segmented control and do not set
  `allowsHitTesting(false)` on it — either change makes the selection jump to the
  new tab instead of morphing across. Ask AI is the fourth tab (to the right of
  Tasks); do not move it back to a full-screen presentation or a bar
  `secondaryAction`.
- **Create (＋) button**: it is a `.buttonStyle(.glass)` button whose label is the
  `matchedTransitionSource`, opening `.popover` with
  `.presentationCompactAdaptation(.popover)` and
  `.navigationTransition(.zoom(sourceID:in:))`. That is the Liquid Glass morph
  the owner asked for; do not replace it with an inline `glassEffectID` panel.
- **Files screen top chrome**: do not drive the navigation bar's visibility from
  a scroll-offset flag. Hiding and showing the bar from that state re-runs
  layout, which is read back as more scrolling and freezes the screen. The
  section switch belongs inside the scroll content so it scrolls away instead.
- **Bottom bar hide on scroll** (`App/BottomBarScrollBehavior.swift`): only a
  user-driven scroll phase may move the bar, and a callback where the content
  size changed is layout, not scrolling (lists correct row heights as rows
  appear). Near the end of a list and just after the bar moves, the state is
  held. Dropping any of these brings back the loop where the bar and the list
  push each other, the bar never returns on scrolling up, and long task lists
  stop scrolling.
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
- Sign-in and purchase are not connected: the screens say so, and no account is
  created from them. The plan screen can select a tier (personal or team), but
  it says plainly that no billing happened: the tier is a local preference
  (`choosePlan`) that unlocks the team share. `MemoraAccount` stays in the model
  for a later phase.
- Team sharing publishes a project or a single record to CloudKit
  (`CloudSharingService`) and lists what teammates share back, for both units.
  It needs the iCloud capability and a container matching the bundle identifier;
  without them, or without an iCloud account, the app says so instead of
  pretending. Shared items are read-only snapshots on the receiver: merging into
  the local editable store, member management, media (audio/photo) sync, and
  conflict handling are not built. A manual package export
  (`makeTeamSharePackage`) also remains.
- The Ask AI fallback never invents answers; when no engine can run it says so.
- The composer defaults to Auto, which follows the configured `AIEngine` and
  cloud selection. Manual choices are saved in `RegisteredLLMStore` and display
  the user's registered model name and provider logo. Both Ask AI paths capture
  `askAIConfiguration` once per question. The summary sheet starts on the model
  Ask AI is using (`defaultSummaryEngineChoice`) and can switch to the settings
  engine, the on-device model, or any registered model for that summary.
- Cloud summaries stream (`CloudAIService.completeStreaming`), so a long answer
  is not cut off by an idle timeout, and an answer stopped at the length limit
  is continued. A failed summary on a record with a transcript retries the
  summary, never the transcription.
- Summaries run through `MeetingSummarizer`, not the Ask AI prompt. 詳細な概要
  (`SummaryTemplate.detailedOverview`) is the base template. The cloud writes
  the whole document in one pass (part notes merged when very long); on-device
  reads section by section with guided generation and `SummaryMarkdownBuilder`
  lays the document out. Actions become tasks (existing titles skipped); owners
  and due dates are only set when the meeting said them. Generated summaries
  render with `MarkdownDocumentView`; cards and rows use `summaryPreview`.
- Icons are SF Symbols named through `MemoraIcon` (`Shared/MemoraIcon.swift`).
  Draw them with `Image(icon:)`, `Label(_:icon:)`, `Button(_:icon:)` and friends
  rather than a literal `systemName`/`systemImage`, so a stored icon resolves the
  same everywhere. Raw values keep the names older builds stored.
- Settings has one entry point: the gear at the bottom right of the side menu
  (`FileSidebarView` footer, beside Memora Plus). Tabs carry no settings button.
  Dark mode is a toggle in Settings › 表示, not in the side menu. The editable
  profile picture remains at the top of Settings, and each Settings section
  uses one tile color (`Tint` in `SettingsView.swift`).
- Backlog and phase status live in `docs/IMPROVEMENT_BACKLOG.md` and
  `docs/OPENCODE_IMPLEMENTATION.md`.
