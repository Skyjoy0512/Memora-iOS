import Foundation

/// How the marketplace groups templates, by the kind of conversation.
enum SummaryTemplateCategory: String, CaseIterable, Identifiable, Codable {
  case meetings
  case customers
  case people
  case projects
  case learning

  var id: Self { self }

  var title: String {
    switch self {
    case .meetings: "会議"
    case .customers: "営業・顧客"
    case .people: "マネジメント・人事"
    case .projects: "企画・プロジェクト"
    case .learning: "学び・インタビュー"
    }
  }
}
