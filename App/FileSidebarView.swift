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
  var onOpenSettings: () -> Void
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      profileHeader

      WorkspaceSwitcher(onCreateTeam: onCreateTeam, onJoinTeam: onJoinTeam)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          sidebarSection("ライブラリ") {
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

          SidebarRow(title: "プロジェクト", symbol: .rectangleStack,
            isSelected: model.selectedTab == .library && model.librarySection == .projects) {
            onOpenProjects()
          }

          sidebarSection("接続") {
            SidebarRow(
              title: isOmiConnected ? "Omi 接続中" : "外部レコーダー",
              symbol: isOmiConnected ? .dotRadiowavesLeftAndRight : .link,
              detail: isOmiConnected ? nil : "未接続"
            ) {
              onOpenRecorder()
            }
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
          if !model.isSignedIn && model.profile.avatarKind == .none {
            ArtworkIcon(artwork: .signIn, size: 22)
              .foregroundStyle(.primary)
              .frame(width: 42, height: 42)
              .background(Color.primary.opacity(0.08), in: Circle())
          } else {
            ProfileAvatar(profile: model.profile, size: 42)
          }

          VStack(alignment: .leading, spacing: 3) {
            Text(displayName)
              .font(.headline)
              .foregroundStyle(.primary)
            Text(accountStatus)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(model.isSignedIn ? "アカウント \(displayName)" : "サインイン")
    }
    .padding(.horizontal, 18)
    .padding(.top, 10)
    .padding(.bottom, 14)
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
          Label(model.isSubscribed ? "Memora Plus" : "Memora Plus にする", icon: .crown)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .memoraGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)

        Spacer(minLength: 8)

        // Settings has one entry point, here; the appearance lives inside it.
        Button {
          InteractionFeedback.shared.send(.tap)
          onOpenSettings()
        } label: {
          Label("設定", icon: .gearshape)
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .memoraGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("プロフィールと設定を開きます")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 10)
  }

  private func sidebarSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)

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
  var title: String
  var symbol: MemoraIcon
  var detail: String?
  var isSelected = false
  var action: () -> Void

  var body: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      HStack(spacing: 14) {
        Image(icon: symbol)
          .font(.body)
          .symbolRenderingMode(.monochrome)
          .frame(width: 24)

        Text(title)
          .font(.body.weight(isSelected ? .semibold : .regular))
          .lineLimit(1)

        Spacer(minLength: 8)

        if let detail {
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      .padding(.horizontal, 14)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.08))
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
