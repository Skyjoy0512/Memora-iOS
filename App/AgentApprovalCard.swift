import SwiftUI

/// Asks before the agent changes anything, and says exactly what will change.
struct AgentApprovalCard: View {
  @Environment(MemoraModel.self) private var model
  var approval: AgentApproval

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(approval.taskDrafts.map { "タスクを\($0.filter(\.isSelected).count)件追加" } ?? approval.title, icon: approval.icon)
        .font(.headline)

      if let drafts = approval.taskDrafts {
        AgentTaskDraftList(drafts: drafts) { draft in model.editAgentTaskDraft(draft, approvalID: approval.id) }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(approval.lines.enumerated()), id: \.offset) { _, line in
            Text(line)
              .font(.subheadline)
              .foregroundStyle(MemoraPalette.cardTextSecondary)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
        }
      }

      HStack(spacing: 10) {
        Button {
          guard model.pendingAgentApproval?.id == approval.id else { return }
          model.resolveAgentApproval(false)
          InteractionFeedback.shared.send(.selection)
        } label: {
          Text("やめる")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)

        Button {
          guard model.pendingAgentApproval?.id == approval.id else { return }
          model.resolveAgentApproval(true)
          InteractionFeedback.shared.send(.selection)
        } label: {
          Text(approval.confirmTitle)
            .font(.body.weight(.semibold))
            .foregroundStyle(MemoraPalette.actionLabel)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(MemoraPalette.action, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(approval.taskDrafts.map { !$0.contains(where: \.isSelected) || !$0.allSatisfy(\.isValid) } ?? false)
      }
    }
    .disabled(model.pendingAgentApproval?.id != approval.id)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      MemoraPalette.card,
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MemoraPalette.border, lineWidth: 1)
    }
  }
}
