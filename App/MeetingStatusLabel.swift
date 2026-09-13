import SwiftUI

struct MeetingStatusLabel: View {
  var status: MeetingStatus

  var body: some View {
    HStack(spacing: 5) {
      if isProcessing {
        ProgressView()
          .controlSize(.mini)
      } else {
        Image(systemName: status.symbol)
      }
      Text(status.shortLabel)
    }
    .font(.caption2.weight(.medium))
    .foregroundStyle(style)
    .accessibilityElement(children: .combine)
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
      AnyShapeStyle(.green)
    case .partialFailure, .failed:
      AnyShapeStyle(.orange)
    default:
      AnyShapeStyle(.secondary)
    }
  }
}
