import Foundation

enum ToolsSection: String, CaseIterable, Identifiable {
  case skills = "マイスキル"
  case templates = "テンプレート"
  case connectors = "コネクタ"

  var id: Self { self }
}
