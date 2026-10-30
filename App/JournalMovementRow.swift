import SwiftUI

/// A run of station passes as one row: the stations and the time span. Tapping
/// opens the list of stops.
struct JournalMovementRow: View {
  var movement: JournalMovement
  var onOpen: (JournalMovement) -> Void
  var connectsToNext = false
  var nextDate: Date?

  var body: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      onOpen(movement)
    } label: {
      JournalTimelineRow(time: movement.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP"))),
        date: movement.start, icon: .tramFill, connectsToNext: connectsToNext, nextDate: nextDate) {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "\(movement.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP"))))〜\(movement.end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP"))))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Text("移動").font(.headline)
          Text(stations.joined(separator: " → "))
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineLimit(3)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
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
