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
        VStack(alignment: .leading, spacing: 4) {
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
      HStack(alignment: .top) {
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

        Spacer()

        Button("閉じる", systemImage: "xmark") {
          onClose()
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
      }

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
    VStack(spacing: 4) {
      Divider()
        .padding(.bottom, 8)

      Toggle(isOn: $prefersDarkAppearance) {
        Label("ダークモード", systemImage: "moon")
          .font(.body.weight(.medium))
      }
      .tint(.primary)
      .frame(minHeight: 48)
      .padding(.horizontal, 20)

      Button {
        onSelectTab(.settings)
      } label: {
        Label("設定とプライバシー", systemImage: "gearshape")
          .font(.body.weight(.medium))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 20)
    }
    .padding(.bottom, 24)
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
      Label(title, systemImage: symbol)
        .font(.body.weight(isSelected ? .semibold : .medium))
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
