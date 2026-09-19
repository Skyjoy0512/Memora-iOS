import Foundation

/// What an Ask AI question looks across.
enum AIChatScope: String, CaseIterable, Identifiable {
  case all
  case files
  case projects

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "すべて"
    case .files: "ファイル"
    case .projects: "プロジェクト"
    }
  }

  var symbol: String {
    switch self {
    case .all: "rectangle.stack"
    case .files: "doc.text"
    case .projects: "folder"
    }
  }

  var scopeLabel: String {
    switch self {
    case .all: "すべての会話"
    case .files: "ファイル"
    case .projects: "プロジェクト"
    }
  }
}
