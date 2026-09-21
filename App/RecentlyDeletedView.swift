import SwiftUI

/// Records that were deleted and can still be brought back, for 30 days.
struct RecentlyDeletedView: View {
  @Environment(MemoraModel.self) private var model
  @State private var pendingDeletion: TrashedRecord?
  @State private var pendingEntryDeletion: TrashedLifeLogEntry?

  var body: some View {
    List {
      if model.trashedRecords.isEmpty && model.trashedLifeLogEntries.isEmpty {
        ContentUnavailableView {
          Label("最近削除した項目はありません", systemImage: "trash")
        } description: {
          Text("削除した記録は30日間ここに残り、いつでも元に戻せます。")
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
      }

      if !model.trashedLifeLogEntries.isEmpty {
        Section("ジャーナル") {
          ForEach(model.trashedLifeLogEntries) { record in
            entryRow(record)
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  pendingEntryDeletion = record
                } label: {
                  Label("完全に削除", systemImage: "trash.slash")
                }
              }
              .swipeActions(edge: .leading) {
                Button {
                  withAnimation {
                    model.restoreTrashedLifeLogEntry(record.id)
                  }
                } label: {
                  Label("復元", systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
              }
          }
        }
      }

      if !model.trashedRecords.isEmpty {
        ForEach(model.trashedRecords) { record in
          row(record)
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                pendingDeletion = record
              } label: {
                Label("完全に削除", systemImage: "trash.slash")
              }
            }
            .swipeActions(edge: .leading) {
              Button {
                withAnimation {
                  model.restoreTrashedRecord(record.id)
                }
              } label: {
                Label("復元", systemImage: "arrow.uturn.backward")
              }
              .tint(.blue)
            }
        }
      }
    }
    .listStyle(.plain)
    .navigationTitle("最近削除した項目")
    .memoraBackButton()
    .confirmationDialog(
      "完全に削除しますか？",
      isPresented: deletionBinding,
      titleVisibility: .visible,
      presenting: pendingDeletion
    ) { record in
      Button("完全に削除", role: .destructive) {
        model.permanentlyDeleteTrashedRecord(record.id)
      }
      Button("キャンセル", role: .cancel) {}
    } message: { _ in
      Text("音声を含めて削除され、元に戻せません。")
    }
    .confirmationDialog(
      "完全に削除しますか？",
      isPresented: entryDeletionBinding,
      titleVisibility: .visible,
      presenting: pendingEntryDeletion
    ) { record in
      Button("完全に削除", role: .destructive) {
        model.permanentlyDeleteTrashedLifeLogEntry(record.id)
      }
      Button("キャンセル", role: .cancel) {}
    } message: { _ in
      Text("写真を含めて削除され、元に戻せません。")
    }
  }

  private func row(_ record: TrashedRecord) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(record.meeting.title)
        .font(.headline)
        .lineLimit(2)

      Text("削除 \(record.deletedAt.formatted(date: .abbreviated, time: .shortened)) ・ 残り\(record.daysRemaining())日")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var deletionBinding: Binding<Bool> {
    Binding {
      pendingDeletion != nil
    } set: { isPresented in
      if !isPresented {
        pendingDeletion = nil
      }
    }
  }

  private func entryRow(_ record: TrashedLifeLogEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(record.entry.title)
        .font(.headline)
        .lineLimit(2)

      Text("削除 \(record.deletedAt.formatted(date: .abbreviated, time: .shortened)) ・ 残り\(record.daysRemaining())日")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var entryDeletionBinding: Binding<Bool> {
    Binding {
      pendingEntryDeletion != nil
    } set: { isPresented in
      if !isPresented {
        pendingEntryDeletion = nil
      }
    }
  }
}
