import SwiftUI

/// The side menu. Besides the tabs, it is where projects live: they are opened
/// and created here rather than from a section of the files tab.
struct FileSidebarView: View {
  @Environment(MemoraModel.self) private var model

  var onSelectTab: (RootTab) -> Void
  var onSelectSpace: (MemoraSpace) -> Void
  var onCreateSpace: () -> Void
  var onOpenSettings: () -> Void
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      profileHeader

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          sidebarSection("メニュー") {
            ForEach(RootTab.allCases) { tab in
              SidebarRow(
                title: tab.title,
                symbol: tab.symbol,
                detail: detail(for: tab),
                isSelected: model.selectedTab == tab
              ) {
                onSelectTab(tab)
              }
            }

          }

          sidebarSection("プロジェクト") {
            ForEach(model.spaces) { space in
              SidebarRow(
                title: space.name,
                symbol: space.icon,
                detail: "\(meetingCount(for: space.id))",
                isSelected: openSpaceID == space.id
              ) {
                onSelectSpace(space)
              }
            }

            SidebarRow(title: "新しいプロジェクト", symbol: .folderBadgePlus) {
              onCreateSpace()
            }
          }

          sidebarSection("接続") {
            SidebarRow(
              title: isOmiConnected ? "Omi 接続中" : "外部レコーダー",
              symbol: isOmiConnected ? .dotRadiowavesLeftAndRight : .link,
              detail: isOmiConnected ? nil : "未接続"
            ) {
              onOpenSettings()
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
        onClose()
        if !model.isSignedIn {
          model.isAuthPresented = true
        }
      } label: {
        HStack(spacing: 12) {
          ProfileAvatar(profile: model.profile, size: 42)

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

  private var footer: some View {
    VStack(spacing: 0) {
      Divider()

      HStack(spacing: 10) {
        Button {
          onClose()
          model.isPaywallPresented = true
        } label: {
          Label(model.isSubscribed ? "Memora Plus" : "Memora Plus にする", icon: .crown)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)

        Spacer(minLength: 8)

        // Settings has one entry point, here; the appearance lives inside it.
        Button("設定", icon: .gearshape, action: onOpenSettings)
          .labelStyle(.iconOnly)
          .font(.body)
          .foregroundStyle(.primary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
          .accessibilityHint("プロフィールと設定を開きます")
      }
      .padding(.leading, 18)
      .padding(.trailing, 10)
      .padding(.vertical, 6)
    }
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

  /// The project on screen, so its row reads as the current place.
  private var openSpaceID: UUID? {
    guard model.selectedTab == .files, case .space(let id) = model.libraryPath.last else { return nil }
    return id
  }

  private func meetingCount(for spaceID: UUID) -> Int {
    model.spaceAggregates[spaceID]?.meetingCount ?? 0
  }

  private func detail(for tab: RootTab) -> String? {
    guard tab == .tasks, openTaskCount > 0 else { return nil }
    return "\(openTaskCount)"
  }

  private var openTaskCount: Int {
    model.tasks.filter { !$0.isCompleted }.count
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
    Button(action: action) {
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
