import SwiftUI

struct MeetingStatusLabel: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var status: MeetingStatus

  var body: some View {
    HStack(spacing: 5) {
      if isProcessing {
        ProgressView()
          .controlSize(.mini)
          .accessibilityHidden(true)
      } else {
        Image(systemName: status.symbol)
          .accessibilityHidden(true)
      }
      Text(status.shortLabel)
        .contentTransition(.opacity)
    }
    .font(.caption2.weight(.medium))
    .foregroundStyle(style)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: status)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.shortLabel)
  }

  private var isProcessing: Bool {
    switch status {
    case .importing, .transcribing, .organizing:
      true
    default:
      false
    }
  }

  private var style: AnyShapeStyle {
    switch status {
    case .ready:
      AnyShapeStyle(.primary)
    case .partialFailure, .failed:
      AnyShapeStyle(.orange)
    default:
      AnyShapeStyle(.secondary)
    }
  }
}
