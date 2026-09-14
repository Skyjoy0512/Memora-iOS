import Foundation

enum FileSection: String, CaseIterable, Identifiable {
  case meetingFiles
  case projects

  var id: Self { self }

  var title: String {
    switch self {
    case .meetingFiles:
      "議事録ファイル"
    case .projects:
      "プロジェクト"
    }
  }

  var symbol: String {
    switch self {
    case .meetingFiles:
      "doc.text"
    case .projects:
      "folder"
    }
  }
}
