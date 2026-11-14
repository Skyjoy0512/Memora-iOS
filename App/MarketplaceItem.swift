import SwiftUI

enum MarketplaceItem: Identifiable {
  case skill(MemoraSkill)
  case template(SummaryMarketTemplate)
  case service(IntegrationCatalog)

  var id: String {
    switch self {
    case .skill(let value): "skill:" + value.id
    case .template(let value): "template:" + value.id
    case .service(let value): "service:" + value.id
    }
  }

  var title: String {
    switch self {
    case .skill(let value): value.name
    case .template(let value): value.title
    case .service(let value): value.name
    }
  }

  var summary: String {
    switch self {
    case .skill(let value): value.summary
    case .template(let value):
      if !value.detail.isEmpty { value.detail }
      else if !value.sections.isEmpty { value.sections.joined(separator: "・") }
      else { "カスタムテンプレート" }
    case .service(let value): value.summary
    }
  }

  var category: String {
    switch self {
    case .skill(let value): value.resolvedCategory.title
    case .template(let value): value.category.title
    case .service(let value): value.isImplemented ? "連携" : "準備中"
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .skill(let value):
      if let name = value.iconIdentifier, let icon = MemoraIcon(rawValue: name) { icon }
      else {
        switch value.id {
        case "project-reading": MemoraIcon.folder
        case "journal-review": MemoraIcon.calendar
        case "project-organize": MemoraIcon.rectangleStack
        case "travel-plan": MemoraIcon.location
        default: MemoraIcon.docRichtext
        }
      }
    case .template(let value): value.symbol
    case .service: AIPluginIcon.resolve(pluginID: id, name: title).icon
    }
  }

  var colors: [Color] {
    switch self {
    case .skill: [Color(red: 0.14, green: 0.32, blue: 0.63), Color(red: 0.36, green: 0.49, blue: 0.80)]
    case .template: [Color(red: 0.49, green: 0.24, blue: 0.43), Color(red: 0.73, green: 0.42, blue: 0.48)]
    case .service: [Color(red: 0.13, green: 0.39, blue: 0.38), Color(red: 0.29, green: 0.56, blue: 0.52)]
    }
  }

  @ViewBuilder var destination: some View {
    switch self {
    case .skill(let value): SkillDetailView(skillID: value.id)
    case .template(let value): SummaryTemplateDetailView(templateID: value.id)
    case .service(let value): IntegrationDetailView(service: value)
    }
  }
}
