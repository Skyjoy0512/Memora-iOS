import SwiftUI

/// Workspace, library utilities and settings remain reachable from the drawer.
struct FileSidebarView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var onOpenRecorder: () -> Void
  var onOpenProjects: () -> Void
  var onCreateTeam: () -> Void
  var onJoinTeam: () -> Void
  var onOpenDocuments: () -> Void
  var onOpenPeople: () -> Void
  var onOpenSettings: () -> Void
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          profileHeader

          WorkspaceSwitcher(onCreateTeam: onCreateTeam, onJoinTeam: onJoinTeam)
            .padding(.horizontal, MemoraSpacing.lg)
            .padding(.bottom, MemoraSpacing.sm)

          VStack(alignment: .leading, spacing: 24) {
            sidebarSection("ライブラリ") {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.hidden)

      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
  }

  private var profileHeader: some View {
    HStack(spacing: 12) {
      Button {
        InteractionFeedback.shared.send(.tap)
        onClose()
        if !model.isSignedIn {
          model.isAuthPresented = true
        }
      } label: {
        HStack(spacing: 12) {
          ProfileAvatar(profile: model.profile, size: 48)

          VStack(alignment: .leading, spacing: 3) {
            Text(displayName)
              .font(.headline)
              .foregroundStyle(.primary)
            Text(accountStatus)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(model.isSignedIn ? "アカウント \(displayName)" : "サインイン")
    }
    .padding(.horizontal, MemoraSpacing.lg)
    .padding(.top, MemoraSpacing.md)
    .padding(.bottom, MemoraSpacing.lg)
  }

  /// The plan and settings float on Liquid Glass, like the app's other
  /// controls, so they read as actions rather than more menu rows.
  private var footer: some View {
    MemoraGlassContainer(spacing: 10) {
      HStack(spacing: 10) {
        Button {
          InteractionFeedback.shared.send(.tap)
          onClose()
          model.isPaywallPresented = true
        } label: {
          Label { Text(dynamicTypeSize.isAccessibilitySize ? "プラン" : "Memora Plus") } icon: {
            MemoraInterfaceIcon(icon: .crown)
          }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, MemoraSpacing.lg)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .memoraGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Memora Plus、プランと利用状況")

        Spacer(minLength: 8)

        // Settings has one entry point, here; the appearance lives inside it.
        Button {
          InteractionFeedback.shared.send(.tap)
          onOpenSettings()
        } label: {
          Label("設定", icon: .gearshape)
            .labelStyle(.iconOnly)
            .font(.system(size: MemoraIconMetrics.glyph, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .memoraGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("プロフィールと設定を開きます")
      }
    }
    .padding(.horizontal, MemoraSpacing.lg)
    .padding(.top, MemoraSpacing.sm)
    .padding(.bottom, MemoraSpacing.md)
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
