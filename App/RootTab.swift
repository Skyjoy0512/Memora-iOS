enum RootTab: String, Hashable, CaseIterable, Identifiable {
  case home
  case files
  case askAI
  case tasks

  var id: Self { self }

  var title: String {
    switch self {
    case .home: "ホーム"
    case .files: "ファイル"
    case .askAI: "Ask AI"
    case .tasks: "タスク"
    }
  }

  var symbol: String {
    switch self {
    case .home: "house"
    case .files: "folder"
    case .askAI: "sparkles"
    case .tasks: "checklist"
    }
  }
}
