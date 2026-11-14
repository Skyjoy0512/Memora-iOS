import SwiftUI

struct MarketplaceHomeView: View {
  @State private var connectionRevision = 0
  var body: some View {
    let skills = MemoraSkill.bundled
    let templates = SummaryTemplateCatalog.market
    let services = IntegrationCatalog.services.filter(\.isImplemented)
    let shelfSkills = ["meeting-followup", "study-quiz", "blog-outline", "packing-shopping-list"]
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

      }
      .padding(.top, MemoraSpacing.xl)
      .padding(.bottom, MemoraSpacing.section)
      .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
  }
}
