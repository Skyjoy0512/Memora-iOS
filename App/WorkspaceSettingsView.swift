import SwiftUI

struct WorkspaceSettingsView: View {
  @State private var isCreatingTeam = false
  @State private var isJoiningTeam = false

  var body: some View {
    MemoraForm {
      WorkspaceSwitcher(onCreateTeam: { isCreatingTeam = true }, onJoinTeam: { isJoiningTeam = true })
    }
    .memoraSettingsPage("ワークスペース")
    .sheet(isPresented: $isCreatingTeam) { TeamCreateSheet() }
    .sheet(isPresented: $isJoiningTeam) { TeamJoinSheet() }
  }
}
