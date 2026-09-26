enum RootTab: String, Hashable, CaseIterable, Identifiable {
  // The order here is the order the tabs appear in, left to right. The raw
  // values stay the case names, so a reorder never changes a saved id.
  case files
  case home
  case tasks

  var id: Self { self }

  var title: String {
    switch self {
    case .home: "ジャーナル"
    case .files: "ファイル"
    case .tasks: "タスク"
    }
  }

  var symbol: String {
    switch self {
    case .home: "calendar"
    case .files: "folder"
    case .tasks: "checklist"
    }
  }
}
