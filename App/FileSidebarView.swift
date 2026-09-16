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

      Divider()
        .padding(.horizontal, 22)

      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          sectionButton(.meetingFiles)
          sectionButton(.projects)

          Divider()
            .padding(.vertical, 10)

          SidebarMenuItemView(title: "ライフログ", symbol: "waveform.path.ecg") {
            onSelectTab(.lifeLog)
          }
          SidebarMenuItemView(title: "タスク", symbol: "checklist") {
            onSelectTab(.tasks)
          }
          SidebarMenuItemView(title: "Ask AI", symbol: "sparkles") {
            onSelectTab(.search)
          }
          SidebarMenuItemView(title: "デバイスと連携", symbol: "antenna.radiowaves.left.and.right") {
            onSelectTab(.settings)
          }
          SidebarMenuItemView(title: "Memora Plus", symbol: "crown") {
            onClose()
            model.isPaywallPresented = true
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
      }
      .scrollIndicators(.hidden)

      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color(uiColor: .secondarySystemBackground))
    .ignoresSafeArea()
  }

  private var profileHeader: some View {
    VStack(alignment: .leading, spacing: 14) {
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
            .font(.title2.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .frame(width: 52, height: 52)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("プロフィール")

      VStack(alignment: .leading, spacing: 4) {
        Text(displayName)
          .font(.title3.bold())
        Text(accountStatus)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        libraryStatus(value: model.meetings.count, label: "ファイル", symbol: "doc.text")
        libraryStatus(value: model.spaces.count, label: "プロジェクト", symbol: "folder")
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 58)
    .padding(.bottom, 20)
  }

  private var footer: some View {
    VStack(spacing: 0) {
      Divider()

      HStack {
        Button("設定とプライバシー", systemImage: "gearshape") {
          onSelectTab(.settings)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .foregroundStyle(.primary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())

        Spacer()

        Button(prefersDarkAppearance ? "システムの外観を使用" : "ダークモード", systemImage: prefersDarkAppearance ? "sun.max" : "moon") {
          prefersDarkAppearance.toggle()
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .foregroundStyle(.primary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .padding(.bottom, 12)
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

  private func libraryStatus(value: Int, label: String, symbol: String) -> some View {
    Label {
      Text("\(value.formatted()) \(label)")
        .font(.caption.weight(.medium))
    } icon: {
      Image(systemName: symbol)
        .font(.caption.weight(.semibold))
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .frame(minHeight: 30)
    .background(Color.primary.opacity(0.055), in: Capsule())
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
          .font(.title3)
          .frame(width: 24)

        Text(title)
          .font(.body.weight(isSelected ? .semibold : .medium))

        Spacer()
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
      .padding(.horizontal, 14)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.primary.opacity(0.08))
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
