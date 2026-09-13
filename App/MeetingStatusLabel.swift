import SwiftUI

struct MeetingStatusLabel: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var status: MeetingStatus

  var body: some View {
    Text(status.shortLabel)
      .contentTransition(.opacity)
    .font(.caption2.weight(.medium))
    .foregroundStyle(style)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: status)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.shortLabel)
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
