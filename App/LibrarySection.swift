enum LibrarySection: String, CaseIterable, Identifiable {
  case files
  case projects

  var id: Self { self }
  var title: String { self == .files ? "記録" : "プロジェクト" }
  var searchPrompt: String { self == .files ? "記録を検索" : "プロジェクト名を検索" }

  static func restored(from value: String?) -> Self {
    value.flatMap(Self.init(rawValue:)) ?? .files
  }
}
