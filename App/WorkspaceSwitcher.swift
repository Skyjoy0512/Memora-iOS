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
        MemoraInterfaceIcon(icon: current.icon)

        VStack(alignment: .leading, spacing: 2) {
          Text(current.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
          Text(current.storageDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        Image(icon: .chevronUpChevronDown)
          .font(.system(size: MemoraIconMetrics.accessory, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(MemoraSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MemoraPalette.secondaryBackground, in: RoundedRectangle(cornerRadius: MemoraRadius.field))
      .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
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
