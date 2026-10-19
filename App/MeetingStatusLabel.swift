import SwiftUI

struct MeetingStatusLabel: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var status: MeetingStatus

  var body: some View {
    Text(status.shortLabel)
      .contentTransition(.opacity)
    .font(MemoraTypography.metadata.weight(.medium))
    .foregroundStyle(style)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: status)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.shortLabel)
  }

  private var style: AnyShapeStyle {
    switch status {
    case .ready:
      AnyShapeStyle(MemoraPalette.textSecondary)
    case .partialFailure:
      AnyShapeStyle(MemoraPalette.warning)
    case .failed:
      AnyShapeStyle(MemoraPalette.danger)
    default:
      AnyShapeStyle(MemoraPalette.textSecondary)
    }
  }
}
