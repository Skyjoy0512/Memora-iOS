import SwiftUI

/// Two actions for a task whose owner a verified voice could not settle. Used
/// where the task is read, so the decision is taken without hunting for it.
struct TaskOwnerConfirmation: View {
  @Environment(MemoraModel.self) private var model
  var task: MemoraTask

  var body: some View {
    HStack(spacing: MemoraSpacing.lg) {
      Button("自分のタスクにする") {
        InteractionFeedback.shared.send(.selection)
        model.confirmTaskOwner(task.id, isMine: true)
      }
      Button("他の人にする") {
        InteractionFeedback.shared.send(.tap)
        model.confirmTaskOwner(task.id, isMine: false)
      }
    }
    .font(MemoraTypography.secondary.weight(.medium))
    .buttonStyle(MemoraQuietButtonStyle())
    .foregroundStyle(AnyShapeStyle(.tint))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("担当を確認")
  }
}
