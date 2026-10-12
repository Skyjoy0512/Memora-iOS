enum RootTab: String, Hashable, CaseIterable, Identifiable {
  case library = "files"
  case home
  case askAI

  var id: Self { self }

  // The library keeps its old saved identifier. Older task/journal selections
  // resolve to Home, where those features are still available.
  static func restored(from value: String) -> Self {
    switch value {
    case "tasks", "journal": .home
    case "library", "projects": .library
    default: Self(rawValue: value) ?? .home
    }
  }

  var artwork: MemoraArtwork? {
    switch self {
    case .home: .journalTab
    case .askAI: .askAITab
    case .library: nil
    }
  }

  var filledArtwork: MemoraArtwork? {
    switch self {
    case .library: .folderSolid
    case .askAI: .askAITabSolid
    case .home: .journalTabSolid
    }
  }

  var title: String {
    switch self {
    case .home: "ジャーナル"
    case .library: "ライブラリ"
    case .askAI: "Ask AI"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .home: .calendar
    case .library: .folder
    case .askAI: .chatBubble
    }
  }

  var filledSymbol: MemoraIcon {
    switch self {
    case .home: .calendarFill
    case .library: .folderFill
    case .askAI: .chatBubbleFill
    }
  }
}
