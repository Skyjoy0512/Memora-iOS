import SwiftUI

/// The stations of one journey, each with its time. From here a stop can be
/// opened, removed, or excluded for the future, and the whole journey can be
/// deleted with one undo.
struct JournalMovementSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var movement: JournalMovement
  @State private var openEntry: LifeLogEntry?
  @State private var isConfirmingDelete = false

  var body: some View {
    NavigationStack {
      List {
        ForEach(movement.entries) { entry in
          Button {
            openEntry = entry
          } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
              Text(Self.stationName(from: entry.title))
                .font(.body)
                .foregroundStyle(.primary)
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(entry.createdAt.formatted(date: .omitted, time: .shortened))、\(Self.stationName(from: entry.title))"
          )
          .accessibilityHint("記録を開きます")
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
              model.deleteLifeLogEntry(entry.id)
              dismiss()
            } label: {
              Label("削除", systemImage: "trash")
            }
          }
        }

        Section {
          Button("この移動を削除", systemImage: "trash", role: .destructive) {
            isConfirmingDelete = true
          }
        }
      }
      .navigationTitle("移動")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
      .confirmationDialog("この移動を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          model.deleteLifeLogEntries(Set(movement.entries.map(\.id)))
          dismiss()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("\(movement.entries.count)件を「最近削除した項目」に移動します。取り消せます。")
      }
      .sheet(item: $openEntry) { entry in
        LifeLogEntryDetailView(entryID: entry.id)
      }
    }
    .presentationDetents([.medium, .large])
  }

  /// The stored "〇〇駅付近を通過" as the station name alone.
  static func stationName(from title: String) -> String {
    title.replacingOccurrences(of: "付近を通過", with: "")
      .replacingOccurrences(of: "を通過", with: "")
  }
}
