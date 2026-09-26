import SwiftUI

/// Navigation for the files tab. The tab bar already carries the app's top
/// level destinations, so this panel stays about one thing: which set of files
/// you are looking at.
struct FileSidebarView: View {
  @Environment(MemoraModel.self) private var model
  @AppStorage("memora.prefersDarkAppearance") private var prefersDarkAppearance = false

  var onSelectTab: (RootTab) -> Void
  var onSelectSection: (FileSection) -> Void
  var onSelectSpace: (MemoraSpace) -> Void
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

            // Ask AI is not a tab; it opens full screen from here or the bar.
            SidebarRow(title: "Ask AI", symbol: "sparkles") {
              onClose()
              model.isAskAIPresented = true
            }
          }

          sidebarSection("ライブラリ") {
            ForEach(FileSection.allCases) { section in
              SidebarRow(
                title: section.title,
                symbol: section.symbol,
                isSelected: model.selectedTab == .files && model.fileSection == section
              ) {
                onSelectSection(section)
              }
            }
          }

          if !model.spaces.isEmpty {
            sidebarSection("最近のプロジェクト") {
              ForEach(model.spaces.prefix(6)) { space in
                SidebarRow(
                  title: space.name,
                  symbol: space.symbol,
                  detail: "\(meetingCount(for: space.id))"
                ) {
                  onSelectSpace(space)
                }
              }
            }
          }

          sidebarSection("接続") {
            SidebarRow(
              title: isOmiConnected ? "Omi 接続中" : "外部レコーダー",
              symbol: isOmiConnected ? "dot.radiowaves.left.and.right" : "link",
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
          Image(systemName: model.isSignedIn ? "person.fill" : "person")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 42, height: 42)
            .background(Color.primary.opacity(0.08), in: Circle())

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

      Button("設定", systemImage: "gearshape", action: onOpenSettings)
        .labelStyle(.iconOnly)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
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
          Label(model.isSubscribed ? "Memora Plus" : "Memora Plus にする", systemImage: "crown")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)

        Spacer(minLength: 8)

        Button(
          prefersDarkAppearance ? "システムの外観にする" : "ダークモードにする",
          systemImage: prefersDarkAppearance ? "sun.max" : "moon"
        ) {
          prefersDarkAppearance.toggle()
        }
        .labelStyle(.iconOnly)
        .font(.body)
        .foregroundStyle(.primary)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
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

  private func meetingCount(for spaceID: UUID) -> Int {
    model.meetings.filter { $0.spaceID == spaceID }.count
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
    model.account?.displayName ?? "ゲスト"
  }

  private var accountStatus: String {
    model.account?.email ?? "このiPhoneに安全に保存"
  }
}

private struct SidebarRow: View {
  var title: String
  var symbol: String
  var detail: String?
  var isSelected = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
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
