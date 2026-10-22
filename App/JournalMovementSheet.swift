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
  @State private var deletionFailed = false

  var body: some View {
    NavigationStack {
      MemoraList {
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
              let deleted = model.handlingPersistenceFailureLocally { model.deleteLifeLogEntry(entry.id) }
              if deleted { dismiss() }
              else { deletionFailed = true }
            } label: {
              Label("削除", icon: .trash)
            }
          }
        }

        Section {
          Button("この移動を削除", icon: .trash, role: .destructive) {
            isConfirmingDelete = true
          }
        }
      }
      .navigationTitle("移動")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
      .confirmationDialog("この移動を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          let deleted = model.handlingPersistenceFailureLocally { model.deleteLifeLogEntries(Set(movement.entries.map(\.id))) }
          if deleted { dismiss() }
          else { deletionFailed = true }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("\(movement.entries.count)件を「最近削除した項目」に移動します。取り消せます。")
      }
      .alert("削除できませんでした", isPresented: $deletionFailed) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("記録は削除していません。保存領域を確認して、もう一度お試しください。")
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
