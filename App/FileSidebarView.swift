import SwiftUI

struct FileSidebarView: View {
  @Environment(MemoraModel.self) private var model
  @AppStorage("memora.prefersDarkAppearance") private var prefersDarkAppearance = false

  var onSelectSection: (FileSection) -> Void
  var onSelectTab: (RootTab) -> Void
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      profileHeader

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          sidebarSection("ライブラリ") {
            sectionButton(.meetingFiles)
            sectionButton(.projects)
          }

          sidebarSection("記録と整理") {
            SidebarMenuItemView(title: "ライフログ", symbol: "waveform.path.ecg") {
              onSelectTab(.lifeLog)
            }
            SidebarMenuItemView(title: "タスク", symbol: "checklist") {
              onSelectTab(.tasks)
            }
          }

          sidebarSection("AIと接続") {
            SidebarMenuItemView(title: "Ask AI", symbol: "sparkles") {
              onSelectTab(.search)
            }
            SidebarMenuItemView(title: "デバイスと連携", symbol: "antenna.radiowaves.left.and.right") {
              onSelectTab(.settings)
            }
          }

          sidebarSection("アカウント") {
            SidebarMenuItemView(title: "Memora Plus", symbol: "crown") {
              onClose()
              model.isPaywallPresented = true
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
      }
      .scrollIndicators(.hidden)

      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color(uiColor: .systemBackground))
    .ignoresSafeArea()
  }

  private var profileHeader: some View {
    HStack(spacing: 12) {
      Button {
        onClose()
        if model.isSignedIn {
          onSelectTab(.settings)
        } else {
          model.isAuthPresented = true
        }
      } label: {
        ZStack {
          Circle()
            .fill(Color.primary.opacity(0.08))
          Image(systemName: model.isSignedIn ? "person.fill" : "person")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("プロフィール")

      VStack(alignment: .leading, spacing: 4) {
        Text(displayName)
          .font(.headline)
        Text(accountStatus)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Button("設定", systemImage: "gearshape") {
        onSelectTab(.settings)
      }
      .labelStyle(.iconOnly)
      .font(.body.weight(.medium))
      .foregroundStyle(.primary)
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
    }
    .padding(.horizontal, 20)
    .padding(.top, 56)
    .padding(.bottom, 18)
  }

  private var footer: some View {
    HStack(spacing: 10) {
      Label(accountStatus, systemImage: model.isSignedIn ? "checkmark.icloud" : "lock")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer(minLength: 8)

      Button(prefersDarkAppearance ? "システムの外観を使用" : "ダークモード", systemImage: prefersDarkAppearance ? "sun.max" : "moon") {
        prefersDarkAppearance.toggle()
      }
      .labelStyle(.iconOnly)
      .font(.body)
      .foregroundStyle(.primary)
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
    }
    .padding(.leading, 22)
    .padding(.trailing, 16)
    .padding(.vertical, 10)
    .padding(.bottom, 10)
    .overlay(alignment: .top) { Divider() }
  }

  private func sectionButton(_ section: FileSection) -> some View {
    SidebarMenuItemView(
      title: section.title,
      symbol: section.symbol,
      isSelected: model.selectedTab == .files && model.fileSection == section
    ) {
      onSelectSection(section)
    }
  }

  private func sidebarSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)

      content()
    }
  }

  private var displayName: String {
    model.account?.displayName ?? "ゲスト"
  }

  private var accountStatus: String {
    if let email = model.account?.email {
      return email
    }
    return "このiPhoneに安全に保存"
  }
}

private struct SidebarMenuItemView: View {
  var title: String
  var symbol: String
  var isSelected = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 16) {
        Image(systemName: symbol)
          .font(.body.weight(.medium))
          .symbolRenderingMode(.monochrome)
          .frame(width: 22)

        Text(title)
          .font(.body.weight(isSelected ? .semibold : .medium))

        Spacer()
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .padding(.horizontal, 12)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(0.07))
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
