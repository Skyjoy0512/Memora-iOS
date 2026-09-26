import SwiftUI

/// A run of station passes as one row: the stations and the time span. Tapping
/// opens the list of stops.
struct JournalMovementRow: View {
  var movement: JournalMovement
  var onOpen: (JournalMovement) -> Void
  @ScaledMetric(relativeTo: .caption) private var timeWidth: CGFloat = 46

  var body: some View {
    Button {
      onOpen(movement)
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Text(movement.start.formatted(date: .omitted, time: .shortened))
          .font(.caption.monospacedDigit().weight(.medium))
          .foregroundStyle(.secondary)
          .frame(width: timeWidth, alignment: .leading)

        VStack(alignment: .leading, spacing: 2) {
          Text(stations.joined(separator: " → "))
            .font(.headline)
            .lineLimit(2)
          Text(
            "\(movement.start.formatted(date: .omitted, time: .shortened))〜\(movement.end.formatted(date: .omitted, time: .shortened))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("移動、\(stations.joined(separator: "、"))")
    .accessibilityHint("各駅の時刻を開きます")
  }

  private var stations: [String] {
    movement.entries.map { JournalMovementSheet.stationName(from: $0.title) }
  }
}
