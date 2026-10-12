import SwiftUI

/// Asks before the agent changes anything, and says exactly what will change.
struct AgentApprovalCard: View {
  @Environment(MemoraModel.self) private var model
  var approval: AgentApproval

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(approval.title, icon: approval.icon)
        .font(.headline)

      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(approval.lines.enumerated()), id: \.offset) { _, line in
          Text(line)
            .font(.subheadline)
            .foregroundStyle(MemoraPalette.cardTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }

      HStack(spacing: 10) {
        Button {
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
      }
    }
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
