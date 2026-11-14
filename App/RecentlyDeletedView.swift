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
          Label("最近削除した項目はありません", icon: .trash)
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
                  Label("完全に削除", icon: .trashSlash)
                }
              }
              .swipeActions(edge: .leading) {
                Button {
                  withAnimation {
                    _ = model.restoreTrashedLifeLogEntry(record.id)
                  }
                } label: {
                  Label("復元", icon: .arrowUturnBackward)
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
                Label("完全に削除", icon: .trashSlash)
              }
            }
            .swipeActions(edge: .leading) {
              Button {
                withAnimation {
                  _ = model.restoreTrashedRecord(record.id)
                }
              } label: {
                Label("復元", icon: .arrowUturnBackward)
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
    } message: { record in
      Text("「\(record.meeting.displayTitle)」を音声を含めて削除します。元に戻せません。")
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
    } message: { record in
      Text("「\(record.entry.title)」を写真を含めて削除します。元に戻せません。")
    }
  }

  private func row(_ record: TrashedRecord) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(record.meeting.title)
        .font(.headline)
        .lineLimit(2)

      Text("削除 \(record.deletedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP")))) ・ 残り\(record.daysRemaining())日")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, MemoraSpacing.xs)
    .accessibilityElement(children: .combine)
    .contextMenu {
      Button("復元", icon: .arrowUturnBackward) { _ = model.restoreTrashedRecord(record.id) }
      Button("完全に削除", icon: .trashSlash, role: .destructive) { pendingDeletion = record }
    }
    .accessibilityAction(named: "復元") { _ = model.restoreTrashedRecord(record.id) }
    .accessibilityAction(named: "完全に削除") { pendingDeletion = record }
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

      Text("削除 \(record.deletedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP")))) ・ 残り\(record.daysRemaining())日")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, MemoraSpacing.xs)
    .accessibilityElement(children: .combine)
    .contextMenu {
      Button("復元", icon: .arrowUturnBackward) { _ = model.restoreTrashedLifeLogEntry(record.id) }
      Button("完全に削除", icon: .trashSlash, role: .destructive) { pendingEntryDeletion = record }
    }
    .accessibilityAction(named: "復元") { _ = model.restoreTrashedLifeLogEntry(record.id) }
    .accessibilityAction(named: "完全に削除") { pendingEntryDeletion = record }
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
