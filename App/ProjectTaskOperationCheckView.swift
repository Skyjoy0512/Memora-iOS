#if DEBUG
import SwiftUI

struct ProjectTaskOperationCheckView: View {
  @Environment(MemoraModel.self) private var model
  @State private var check = ProjectTaskOperationCheck()
  @State private var isShowingTasks = false

  var body: some View {
    MemoraList {
      Text("モデル・外部APIは使いません。架空の記録2件とタスク6件を実際に保存します。検証画面を閉じると今回のデータだけを削除します。")
        .font(.footnote).foregroundStyle(.secondary)
      Button("関連タスクの検証データを作成") { check.start(in: model) }
        .disabled(check.projectID != nil || model.currentTeamID != nil || model.isRestoring || model.isStoreProtected)
      Text(check.result).textSelection(.enabled)
      if check.projectID != nil {
        Button("関連タスク画面を開く") { isShowingTasks = true }
        Button("編集後の保存を確認") { check.verify(in: model) }
        Button("検証データを削除", role: .destructive) { check.cleanup(in: model) }
      }
    }
    .navigationTitle("関連タスクの検証").navigationBarTitleDisplayMode(.inline)
    .tint(MemoraPalette.textPrimary)
    .sheet(isPresented: $isShowingTasks) {
      if let projectID = check.projectID {
        NavigationStack {
          ProjectTasksView(projectID: projectID)
            .navigationDestination(for: LibraryRoute.self) { route in LibraryDestinationView(route: route) }
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { isShowingTasks = false }
              }
            }
        }
      }
    }
    .onDisappear { if !isShowingTasks { check.cleanup(in: model) } }
  }
}
#endif
