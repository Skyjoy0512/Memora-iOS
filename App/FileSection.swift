import Foundation

enum FileSection: String, CaseIterable, Identifiable {
  case meetingFiles
  case projects
  case people

  var id: Self { self }

  var title: String {
    switch self {
    case .meetingFiles:
      "ファイル"
    case .projects:
      "プロジェクト"
    case .people:
      "人"
    }
  }

  var symbol: String {
    switch self {
    case .meetingFiles:
      "doc.text"
    case .projects:
      "square.stack.3d.up"
    case .people:
      "person.2"
    }
  }
}
