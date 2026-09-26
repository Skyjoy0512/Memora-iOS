enum RootTab: String, Hashable, CaseIterable, Identifiable {
  // The order here is the order the tabs appear in, left to right. The raw
  // values stay the case names, so a reorder never changes a saved id.
  case files
  case home
  case tasks
  case askAI

  var id: Self { self }

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
    case .askAI: .sparkles
    case .tasks: .checklist
    }
  }

  /// The filled form the tab bar draws, so the segments read as solid shapes.
  var filledSymbol: MemoraIcon {
    switch self {
    case .home: .calendarFill
    case .files: .folderFill
    case .askAI: .sparklesFill
    case .tasks: .checklistFill
    }
  }
}
