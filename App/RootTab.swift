enum RootTab: String, Hashable, CaseIterable, Identifiable {
  // The order here is the order the tabs appear in, left to right. The raw
  // values stay the case names, so a reorder never changes a saved id.
  case files
  case home
  case tasks
  case askAI

  var id: Self { self }

  var artwork: MemoraArtwork? {
    switch self {
    case .home: .journalTab
    case .askAI: .askAITab
    case .files, .tasks: nil
    }
  }

  var filledArtwork: MemoraArtwork? {
    switch self {
    case .files: .folderSolid
    case .home: .journalTabSolid
    case .askAI: .askAITabSolid
    case .tasks: nil
    }
  }

  var title: String {
    switch self {
    case .home: "ジャーナル"
    case .files: "ファイル"
    case .askAI: "Ask AI"
    case .tasks: "タスク"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .home: .calendar
    case .files: .folder
    case .askAI: .chatBubble
    case .tasks: .checklist
    }
  }

  var filledSymbol: MemoraIcon {
    switch self {
    case .home: .calendarFill
    case .files: .folderFill
    case .askAI: .chatBubbleFill
    case .tasks: .checklistFill
    }
  }
}
