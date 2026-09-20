# AGENTS.md — Memora

SwiftUI app for iPhone (iOS 18 deployment target, built against the iOS 27 SDK).
App sources live in `App/`, configuration in `Project.json`, design notes in
`DESIGN.md` and `MCP.md`.

## Working agreement

- Change the UI, layout, or copy only when the request asks for it. Otherwise
  optimise and refactor code without altering what is on screen.
- Build after every change and keep the working tree committed.
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

- A recording in progress has no discard path: closing the capture sheet keeps
  recording, and `MemoraModel.cancelCapture()` is defined but not wired to any UI.
- Cloud storage, MCP, Google Drive, on-device Whisper and local LLM are
  preferences only; the services behind them are not implemented.
