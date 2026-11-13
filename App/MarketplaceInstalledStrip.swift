import SwiftUI

struct MarketplaceInstalledStrip: View {
  var connectionRevision = 0
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var connectedIDs: Set<String> = []

  var body: some View {
    let items = IntegrationCatalog.services.filter { connectedIDs.contains($0.id) }.map(MarketplaceItem.service)
      + model.installedMarketTemplates.map(MarketplaceItem.template)
      + model.skillCatalog.filter { !model.disabledSkillIDs.contains($0.id) }.map(MarketplaceItem.skill)
    let visibleCount = typeSize.isAccessibilitySize ? 3 : 5

    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      NavigationLink { MarketplaceInstalledView() } label: {
        HStack(spacing: MemoraSpacing.sm) {
          Text("利用中").font(.headline)
          Image(icon: .chevronRight, size: 12).accessibilityHidden(true)
        }
        .foregroundStyle(MemoraPalette.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      }
      .accessibilityLabel("利用中の項目をすべて見る")
      .accessibilityAddTraits(.isHeader)
      if items.isEmpty {
        Text("まだ利用中の項目はありません")
          .font(.subheadline).foregroundStyle(MemoraPalette.textSecondary)
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: MemoraSpacing.md) {
            ForEach(items.prefix(visibleCount)) { item in
              MarketplaceItemLink(item: item, onConnectorDismiss: refreshConnections) {
                MarketplaceItemIcon(item: item)
              }
              .accessibilityLabel(item.title)
            }
            if items.count > visibleCount {
              NavigationLink { MarketplaceInstalledView() } label: {
                Text("+\(items.count - visibleCount)")
                  .font(.body.weight(.semibold))
                  .monospacedDigit()
                  .fixedSize()
                  .padding(.horizontal, MemoraSpacing.md)
                  .frame(minWidth: 48, minHeight: 48)
                  .background(MemoraPalette.selection, in: RoundedRectangle(cornerRadius: 12))
              }
              .accessibilityLabel("ほか\(items.count - visibleCount)件の利用中の項目")
            }
          }
        }
        .scrollIndicators(.hidden)
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, MemoraSpacing.screen)
    .onAppear(perform: refreshConnections)
    .onChange(of: connectionRevision) { _, _ in refreshConnections() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { refreshConnections() }
    }
  }

  private func refreshConnections() {
    connectedIDs = Set(IntegrationCatalog.services.filter { model.integrationHasConnection($0.id) }.map(\.id))
  }
}
