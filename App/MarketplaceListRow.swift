import SwiftUI

struct MarketplaceListRow: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var typeSize
  var item: MarketplaceItem
  var badge: String?
  var onConnectorDismiss: (() -> Void)?
  @State private var showsDetail = false
  @State private var isConnected = false

  var body: some View {
    HStack(alignment: .center, spacing: MemoraSpacing.md) {
      Button { showsDetail = true } label: {
        HStack(spacing: MemoraSpacing.lg) {
          MarketplaceItemIcon(item: item)
          VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
            Text(item.title).font(.body)
              .foregroundStyle(MemoraPalette.textPrimary)
            Text(badge ?? item.summary).font(.subheadline)
              .foregroundStyle(MemoraPalette.textSecondary)
              .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
          }
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
      }
      .accessibilityIdentifier("marketplace.item.\(item.id)")

      if isInUse {
        Menu {
          Button("詳細を表示", icon: .infoCircle) { showsDetail = true }
          switch item {
          case .skill(let skill):
            Button("無効にする", icon: .minusCircle) { model.setSkillEnabled(skill.id, enabled: false) }
          case .template(let template):
            if !template.isCustom {
              Button("要約の選択肢から外す", icon: .minusCircle) { model.uninstallTemplate(template.id) }
            }
          case .service:
            Button("接続を管理", icon: .gearshape) { showsDetail = true }
          }
        } label: {
          Label("\(item.title)の操作", icon: .ellipsis)
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
      } else if case .service(let service) = item, !service.isImplemented {
        Text("準備中").font(.caption).foregroundStyle(MemoraPalette.textSecondary)
      } else {
        Button {
          switch item {
          case .template(let template): model.installTemplate(template.id)
          case .skill(let skill): model.setSkillEnabled(skill.id, enabled: true)
          case .service: showsDetail = true
          }
        } label: {
          Label("\(item.title)を追加・接続", icon: .plus)
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(MemoraPalette.textSecondary)
    .padding(.vertical, MemoraSpacing.sm)
    .fullScreenCover(isPresented: $showsDetail, onDismiss: refreshConnection) {
      MarketplaceDetailSheet(item: item)
    }
    .onAppear { updateConnection() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { updateConnection() }
    }
  }

  private var isInUse: Bool {
    switch item {
    case .skill(let skill): !model.disabledSkillIDs.contains(skill.id)
    case .template(let template): model.isTemplateAvailable(template.id)
    case .service: isConnected
    }
  }

  private func updateConnection() {
    if case .service(let service) = item {
      isConnected = model.integrationHasConnection(service.id)
    }
  }

  private func refreshConnection() {
    updateConnection()
    onConnectorDismiss?()
  }
}
