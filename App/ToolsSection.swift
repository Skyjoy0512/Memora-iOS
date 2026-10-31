import Foundation

enum ToolsSection: String, CaseIterable, Identifiable {
  case skills = "マイスキル"
  case templates = "テンプレート"
  case connectors = "コネクタ"

  var id: Self { self }
  var title: String {
    switch self {
    case .skills: "スキル"
    case .templates: "要約テンプレート"
    case .connectors: "コネクタ"
    }
  }
}
