#if DEBUG
import SwiftUI

struct AgentTaskOperationCheckView: View {
  @Environment(MemoraModel.self) private var model
  @State private var check = AgentTaskOperationCheck()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("モデル・外部APIは使いません。承認すると検証タスクを実際に保存し、この画面を閉じる際に検証データだけを削除します。個人ワークスペースで実行できます。")
          .font(.footnote).foregroundStyle(.secondary)
        if let approval = model.pendingAgentApproval, approval.messageID == check.messageID {
          AgentApprovalCard(approval: approval)
        }
        Text(check.result).font(.body).textSelection(.enabled)
        ForEach(model.tasks.filter { check.savedIDs.contains($0.id) }) { task in
          VStack(alignment: .leading, spacing: 4) {
            Text(task.title).font(.headline)
            if !task.detail.isEmpty { Text(task.detail).font(.footnote) }
            if let assignee = task.assignee { Text(assignee).font(.caption) }
            if let dueDate = task.dueDate { Text(dueDate, style: .date).font(.caption) }
          }
        }
        if check.isRunning {
          Button("検証を停止", icon: .stopFill) { check.stop(in: model) }
        } else {
          Button("承認と保存を検証", icon: .checklist) { check.start(in: model) }
            .disabled(model.isAIChatResponding || model.pendingAgentApproval != nil || model.currentTeamID != nil)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(MemoraSpacing.lg)
    }
    .tint(MemoraPalette.textPrimary)
    .background(MemoraPalette.background)
    .navigationTitle("ローカル操作の検証").navigationBarTitleDisplayMode(.inline)
    .onDisappear { check.cleanup(in: model) }
  }
}
#endif
