import Foundation

enum FileSection: String, CaseIterable, Identifiable {
  case meetingFiles
  case projects

  var id: Self { self }

  var title: String {
    switch self {
    case .meetingFiles:
      "議事録"
    case .projects:
      "プロジェクト"
    }
  }

  var symbol: String {
    switch self {
    case .meetingFiles:
      "doc.text"
    case .projects:
      "square.stack.3d.up"
    }
  }
}
