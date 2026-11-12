import SwiftUI

struct MarketplaceHomeView: View {
  @State private var connectionRevision = 0
  var body: some View {
    let skills = MemoraSkill.bundled
    let templates = SummaryTemplateCatalog.market
    let services = IntegrationCatalog.services.filter(\.isImplemented)
    let shelfSkills = ["meeting-followup", "meeting-preparation", "proposal", "decision-timeline"]
      .compactMap { id in skills.first { $0.id == id } }.map(MarketplaceItem.skill)
    let shelfTemplates = ["content.video", "market.regular", "market.designReview", "market.incidentReview"]
      .compactMap { id in templates.first { $0.id == id } }.map(MarketplaceItem.template)

    ScrollView {
      LazyVStack(alignment: .leading, spacing: MemoraSpacing.section) {
        MarketplaceInstalledStrip(connectionRevision: connectionRevision)
        MarketplaceShelf(section: .connectors, items: services.map(MarketplaceItem.service),
          onConnectorDismiss: { connectionRevision += 1 })
        MarketplaceShelf(section: .skills, items: shelfSkills)
        MarketplaceShelf(section: .templates, items: shelfTemplates)
        NavigationLink { CommunityCatalogView() } label: {
          HStack(spacing: MemoraSpacing.sm) {
            Text("コミュニティ").font(.headline)
            Image(icon: .chevronRight, size: 12).accessibilityHidden(true)
          }
          .foregroundStyle(MemoraPalette.textSecondary)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MemoraSpacing.screen)
        VStack(spacing: MemoraSpacing.sm) {
          NavigationLink { SkillsView() } label: {
            Label("マイスキルを管理", icon: .sliderHorizontal3)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
          NavigationLink { SummaryTemplateMarketplaceView() } label: {
            Label("マイテンプレートを管理", icon: .docOnDoc)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .padding(.horizontal, MemoraSpacing.screen)
      }
      .padding(.top, MemoraSpacing.xl)
      .padding(.bottom, MemoraSpacing.section)
      .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
  }
}
