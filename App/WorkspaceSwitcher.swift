import SwiftUI

/// One current workspace, selected directly from the visible list.
struct WorkspaceSwitcher: View {
  @Environment(MemoraModel.self) private var model
  var onCreateTeam: () -> Void
  var onJoinTeam: () -> Void

  var body: some View {
    Section {
      ForEach(model.workspaces) { workspace in
        WorkspaceSelectionRow(workspace: workspace, isSelected: model.currentWorkspace == workspace) {
          model.selectWorkspace(workspace)
        }
      }
    } header: {
      Text("ワークスペースを選択")
    } footer: {
      Text("チェックの付いた保存先を使用します。個人の記録はこの端末に保存し、チームを選ぶとそのワークスペースに切り替わります。")
    }

    Section {
      if model.teamBackend is UnconfiguredTeamBackend {
        SettingsValue(title: "チームワークスペース", value: "未接続", icon: .person2)
        Text("チームの作成と参加は、サービス接続後に利用できます。")
          .font(.footnote).foregroundStyle(.secondary)
      } else {
        Button("チームを作成", icon: .plus, action: onCreateTeam)
        Button("チームに参加", icon: .personBadgePlus, action: onJoinTeam)
      }
    }
    .task { await model.refreshTeams() }
  }
}
