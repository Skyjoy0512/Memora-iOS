import SwiftUI

/// The stations of one journey, each with its time, opened from the movement row.
struct JournalMovementSheet: View {
  @Environment(\.dismiss) private var dismiss
  var movement: JournalMovement

  var body: some View {
    NavigationStack {
      List {
        ForEach(movement.entries) { entry in
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
            Text(Self.stationName(from: entry.title))
              .font(.body)
            Spacer(minLength: 0)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            "\(entry.createdAt.formatted(date: .omitted, time: .shortened))、\(Self.stationName(from: entry.title))"
          )
        }
      }
      .navigationTitle("移動")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
  }

  /// The stored "〇〇駅付近を通過" as the station name alone.
  static func stationName(from title: String) -> String {
    title.replacingOccurrences(of: "付近を通過", with: "")
      .replacingOccurrences(of: "を通過", with: "")
  }
}
