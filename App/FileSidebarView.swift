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
          SidebarMenuItemView(title: "Ask AI", symbol: "sparkles") {
            onSelectTab(.search)
          }
          SidebarMenuItemView(title: "リスト", symbol: "checklist") {
            onSelectTab(.tasks)
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
    .background(Color(uiColor: .systemBackground))
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

      VStack(alignment: .leading, spacing: 3) {
        Text(displayName)
          .font(.title3.bold())
        Text(userID)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 18) {
        profileCount(value: 0, label: "フォロー")
        profileCount(value: 0, label: "フォロワー")
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

  private func profileCount(value: Int, label: String) -> some View {
    HStack(spacing: 4) {
      Text(value.formatted())
        .font(.subheadline.bold())
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var displayName: String {
    model.account?.displayName ?? "ゲスト"
  }

  private var userID: String {
    guard let email = model.account?.email,
          let localPart = email.split(separator: "@").first else {
      return "@memora"
    }
    return "@\(localPart)"
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
