enum RootTab: String, Hashable, CaseIterable, Identifiable {
  case home
  case library = "files"
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

  var artwork: MemoraArtwork? { self == .askAI ? .askAITab : nil }

  var filledArtwork: MemoraArtwork? {
    switch self {
    case .library: .folderSolid
    case .askAI: .askAITabSolid
    default: nil
    }
  }

  var title: String {
    switch self {
    case .home: "ホーム"
    case .library: "ライブラリ"
    case .askAI: "Ask AI"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .home: .house
    case .library: .folder
    case .askAI: .chatBubble
    }
  }

  var filledSymbol: MemoraIcon {
    switch self {
    case .home: .houseFill
    case .library: .folderFill
    case .askAI: .chatBubbleFill
    }
  }
}
