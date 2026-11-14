import Foundation

enum MarketplaceScope: String, CaseIterable, Identifiable {
  case all
  case skills
  case templates
  case connectors

  var id: Self { self }

  var section: ToolsSection? {
    switch self {
    case .all: nil
    case .skills: .skills
    case .templates: .templates
    case .connectors: .connectors
    }
  }

  var title: String { section?.title ?? "マーケットプレイス" }
  var shortTitle: String {
    switch self {
    case .all: "すべて"
    case .skills: "スキル"
    case .templates: "要約"
    case .connectors: "コネクタ"
    }
  }
}
