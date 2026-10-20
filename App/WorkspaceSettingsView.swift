import SwiftUI

struct WorkspaceSettingsView: View {
  @State private var isCreatingTeam = false
  @State private var isJoiningTeam = false

  var body: some View {
    MemoraForm {
      Section {
        WorkspaceSwitcher(onCreateTeam: { isCreatingTeam = true }, onJoinTeam: { isJoiningTeam = true })
      } footer: {
        Text("個人の記録はこの端末に保存します。チームを選ぶと、そのワークスペースに切り替わります。")
      }
    }
    .memoraSettingsPage("ワークスペース")
    .sheet(isPresented: $isCreatingTeam) { TeamCreateSheet() }
    .sheet(isPresented: $isJoiningTeam) { TeamJoinSheet() }
  }
}
