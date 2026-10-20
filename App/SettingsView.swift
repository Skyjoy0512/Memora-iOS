import SwiftUI

struct SettingsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var showsCloseButton = true
  @State private var isProfileEditorPresented = false

  var body: some View {
    let groups = SettingsCategory.groups.map { group in
      (group, SettingsCategory.allCases.filter { $0.group == group })
    }
    NavigationStack {
      Form {
        Section {
          Button { isProfileEditorPresented = true } label: {
            HStack(spacing: MemoraSpacing.lg) {
              ProfileAvatar(profile: model.profile, size: 48)
              VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
                Text(profileName).font(MemoraTypography.body.weight(.semibold))
                Text("プロフィールを編集")
                  .font(MemoraTypography.metadata)
                  .foregroundStyle(MemoraPalette.textSecondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Image(icon: .chevronRight, size: MemoraIconMetrics.accessory)
                .font(.system(size: MemoraIconMetrics.accessory, weight: .semibold))
                .foregroundStyle(MemoraPalette.textSecondary)
                .accessibilityHidden(true)
            }
            .foregroundStyle(MemoraPalette.textPrimary)
            .padding(.vertical, MemoraSpacing.sm)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("プロフィール \(profileName)")
          .accessibilityHint("ミー文字・写真・名前を編集します")
          .accessibilityIdentifier("settings.profile")
        }
        ForEach(groups, id: \.0) { group, categories in
          Section(group) {
            ForEach(categories) { category in
              NavigationLink(value: category) {
                if let value = value(for: category) {
                  SettingsValue(title: category.title, value: value, icon: category.icon)
                } else {
                  SettingsLabel(category.title, icon: category.icon)
                }
              }
              .accessibilityIdentifier("settings.category.\(category.rawValue)")
            }
          }
        }
      }
      .memoraSettingsPage("設定")
      .navigationDestination(for: SettingsCategory.self) { category in
        SettingsCategoryView(category: category) {
          if showsCloseButton { dismiss() }
        }
      }
      .toolbar {
        if showsCloseButton {
          ToolbarItem(placement: .confirmationAction) {
            ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
          }
        }
      }
      .sheet(isPresented: $isProfileEditorPresented) { ProfileEditorView() }
    }
    .accessibilityIdentifier("settings")
  }

  private func value(for category: SettingsCategory) -> String? {
    switch category {
    case .account: model.isSignedIn ? "サインイン済み" : "このiPhoneのみ"
    case .workspace: model.currentWorkspace.title
    case .plan: model.planName
    default: nil
    }
  }

  private var profileName: String {
    let name = model.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? model.account?.displayName ?? "名前を設定" : name
  }
}
