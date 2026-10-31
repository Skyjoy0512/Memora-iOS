import SwiftUI

struct MarketplaceHomeView: View {

  var body: some View {
    let skills = MemoraSkill.bundled
    let templates = SummaryTemplateCatalog.market
    let services = IntegrationCatalog.services.filter(\.isImplemented)
    let featured = skills.first { $0.id == "meeting-followup" } ?? skills.first

    ScrollView {
      VStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
        if let featured {
          let item = MarketplaceItem.skill(featured)
          NavigationLink { item.destination } label: { MarketplaceCard(item: item, featured: true) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("marketplace.featured")
            .padding(.horizontal, MemoraSpacing.screen)
        }
        MarketplaceShelf(section: .skills, items: skills.prefix(6).map(MarketplaceItem.skill))
        MarketplaceShelf(section: .templates, items: templates.prefix(6).map(MarketplaceItem.template))
        MarketplaceShelf(section: .connectors, items: services.map(MarketplaceItem.service))

        VStack(spacing: 0) {
          NavigationLink { SkillsView() } label: {
            Label("マイスキルを管理", icon: .sliderHorizontal3)
              .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
          }
          Divider()
          NavigationLink { SummaryTemplateMarketplaceView() } label: {
            Label("マイテンプレートを管理", icon: .docOnDoc)
              .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
          }
        }
        .font(.subheadline)
        .padding(.horizontal, MemoraSpacing.screen)
      }
      .padding(.top, MemoraSpacing.md)
      .padding(.bottom, MemoraSpacing.section)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
  }
}
