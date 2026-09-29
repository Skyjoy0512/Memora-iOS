import SwiftUI

/// The agent's work so far, one line per step, so the person can follow which
/// records it read and what it changed.
struct AgentStepsView: View {
  var steps: [AgentStep]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(steps) { step in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Image(icon: step.icon)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(width: 18)

          VStack(alignment: .leading, spacing: 1) {
            Text(step.title)
              .font(.subheadline)
              .foregroundStyle(step.state == .declined ? .secondary : .primary)
              .strikethrough(step.state == .declined)
            if let detail = step.detail, !detail.isEmpty {
              Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 8)

          stateMark(step.state)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(stateLabel(step.state))
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  @ViewBuilder
  private func stateMark(_ state: AgentStep.State) -> some View {
    switch state {
    case .running:
      ProgressView()
        .controlSize(.mini)
    case .done:
      Image(icon: .checkmark)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tint)
    case .declined:
      Image(icon: .xmark)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    case .failed:
      Image(icon: .exclamationmarkTriangle)
        .font(.caption)
        .foregroundStyle(.orange)
    }
  }

  private func stateLabel(_ state: AgentStep.State) -> String {
    switch state {
    case .running: "実行中"
    case .done: "完了"
    case .declined: "取りやめ"
    case .failed: "失敗"
    }
  }
}
