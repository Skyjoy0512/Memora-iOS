import SwiftUI

/// The side menu's switch between the personal workspace and teams, with
/// creating and joining a team beside the list.
struct WorkspaceSwitcher: View {
  @Environment(MemoraModel.self) private var model
  var onCreateTeam: () -> Void
  var onJoinTeam: () -> Void

  var body: some View {
    let current = model.currentWorkspace

    Menu {
      Picker("ワークスペース", selection: selection) {
        ForEach(model.workspaces) { workspace in
          Label(workspace.title, icon: workspace.icon)
            .tag(workspace)
        }
      }
      .pickerStyle(.inline)

      Section {
        Button("チームを作成", icon: .plus, action: onCreateTeam)
        Button("チームに参加", icon: .personBadgePlus, action: onJoinTeam)
      }
    } label: {
      HStack(spacing: 12) {
        Image(icon: current.icon)
          .font(.body.weight(.semibold))
          .foregroundStyle(.tint)
          .frame(width: 36, height: 36)
          .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .leading, spacing: 2) {
          Text(current.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(current.storageDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Image(icon: .chevronUpChevronDown)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .memoraCard(radius: 14)
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("ワークスペース")
    .accessibilityValue("\(current.title)、\(current.storageDescription)")
    .task { await model.refreshTeams() }
  }

  private var selection: Binding<Workspace> {
    Binding {
      model.currentWorkspace
    } set: { workspace in
      model.selectWorkspace(workspace)
    }
  }
}
