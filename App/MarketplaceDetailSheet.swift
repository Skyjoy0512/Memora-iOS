import SwiftUI

struct MarketplaceDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  var item: MarketplaceItem

  var body: some View {
    NavigationStack {
      switch item {
      case .skill(let skill): SkillDetailView(skillID: skill.id, isMarketplaceSheet: true)
      case .template(let template): SummaryTemplateDetailView(templateID: template.id, isMarketplaceSheet: true)
      case .service(let service):
        IntegrationDetailView(service: service)
          .toolbar {
            ToolbarActionItem(placement: .topBarLeading) {
              ToolbarIconButton("閉じる", icon: .chevronLeft) { dismiss() }
            }
          }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.hidden)
    .presentationCornerRadius(32)
  }
}
