import SwiftUI

/// Workspace, library utilities and settings remain reachable from the drawer.
struct FileSidebarView: View {
  @Environment(MemoraModel.self) private var model

  var onOpenRecorder: () -> Void
  var onOpenProjects: () -> Void
  var onCreateTeam: () -> Void
  var onJoinTeam: () -> Void
  var onOpenDocuments: () -> Void
  var onOpenPeople: () -> Void
  var onSelectTab: (RootTab) -> Void
  var onOpenTools: () -> Void
  var onOpenSettings: () -> Void
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          WorkspaceSwitcher(onCreateTeam: onCreateTeam, onJoinTeam: onJoinTeam)
            .padding(.horizontal, MemoraSpacing.lg)
            .padding(.top, MemoraSpacing.md)
            .padding(.bottom, MemoraSpacing.sm)

          VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
            VStack(spacing: 0) {
              SidebarRow(title: "ホーム", symbol: .house,
                isSelected: model.selectedTab == .home) {
                onSelectTab(.home)
              }
              SidebarRow(title: "ライブラリ", symbol: .folder,
                isSelected: model.selectedTab == .library) {
                onSelectTab(.library)
              }
              SidebarRow(title: "Ask AI", symbol: .sparkles,
                isSelected: model.selectedTab == .askAI) {
                onSelectTab(.askAI)
              }
              SidebarRow(title: "ツール", symbol: .puzzle) {
                onOpenTools()
              }
            }

            sidebarSection("コレクション") {
              SidebarRow(title: "プロジェクト", symbol: .rectangleStack,
                isSelected: model.selectedTab == .library && model.librarySection == .projects) {
                onOpenProjects()
              }
              SidebarRow(
                title: "資料",
                symbol: .docRichtext,
                detail: model.documents.isEmpty ? nil : "\(model.documents.count)",
                isSelected: isShowingDocuments
              ) {
                onOpenDocuments()
              }

              SidebarRow(
                title: "人物",
                symbol: .person2,
                detail: model.people.isEmpty ? nil : "\(model.people.count)",
                isSelected: model.selectedTab == .library && model.libraryPath.first == .people
              ) {
                onOpenPeople()
              }
            }

            sidebarSection("デバイス") {
              SidebarRow(
                title: "外部レコーダー",
                symbol: .dotRadiowavesLeftAndRight,
                detail: isOmiConnected ? "接続中" : "未接続"
              ) {
                onOpenRecorder()
              }
            }
          }
          .padding(.horizontal, MemoraSpacing.lg)
          .padding(.vertical, MemoraSpacing.md)
          .accessibilityIdentifier("sidebar.navigation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.hidden)

      SidebarAccountFooter(profile: model.profile, displayName: displayName,
        accountStatus: accountStatus, isSignedIn: model.isSignedIn) {
          InteractionFeedback.shared.send(.tap)
          onClose()
          if !model.isSignedIn { model.isAuthPresented = true }
        } onPlan: {
          InteractionFeedback.shared.send(.tap)
          onClose()
          model.isPaywallPresented = true
        } onSettings: {
          InteractionFeedback.shared.send(.tap)
          onOpenSettings()
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(MemoraPalette.secondaryBackground.ignoresSafeArea())
  }

  private func sidebarSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(MemoraTypography.metadata.weight(.medium))
        .foregroundStyle(MemoraPalette.textSecondary)
        .padding(.horizontal, MemoraSpacing.lg)
        .padding(.bottom, MemoraSpacing.xxs)

      content()
    }
  }

  private var isShowingDocuments: Bool {
    model.selectedTab == .library && model.libraryPath.first == .documents
  }

  private var isOmiConnected: Bool {
    if case .connected = model.omiPairingManager.state { return true }
    return false
  }

  private var displayName: String {
    let name = model.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return model.account?.displayName ?? (name.isEmpty ? "ゲスト" : name)
  }

  private var accountStatus: String {
    model.account?.email ?? "このiPhoneに安全に保存"
  }
}

private struct SidebarRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var title: String
  var symbol: MemoraIcon
  var detail: String?
  var isSelected = false
  var action: () -> Void

  var body: some View {
    let labelLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.sm))
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      HStack(spacing: MemoraSpacing.md) {
        MemoraInterfaceIcon(icon: symbol)

        labelLayout {
          Text(title)
            .font(.body.weight(isSelected ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true)
          if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: MemoraSpacing.sm) }
          if let detail {
            Text(detail)
              .font(.subheadline)
              .foregroundStyle(MemoraPalette.textSecondary)
              .monospacedDigit()
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .padding(.horizontal, MemoraSpacing.lg)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: MemoraRadius.field, style: .continuous)
            .fill(MemoraPalette.selection)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.field, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
