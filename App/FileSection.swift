import Foundation

enum FileSection: String, CaseIterable, Identifiable {
  case meetingFiles
  case projects

  var id: Self { self }

  var title: String {
    switch self {
    case .meetingFiles:
      "ファイル"
    case .projects:
      "プロジェクト"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .meetingFiles:
      .docText
    case .projects:
      .squareStack3dUp
    }
  }
}
