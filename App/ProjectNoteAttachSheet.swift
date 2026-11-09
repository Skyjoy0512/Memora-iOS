import SwiftUI

/// Links existing sources from the note's own save destination to the note.
/// Nothing is copied, moved or deleted; the note only gains references.
struct ProjectNoteAttachSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var noteID: UUID
  @State private var selection = NoteAttachmentSelection()
  @State private var failure: String?
  @State private var query = ""

  private var remainingCapacity: Int {
    max(0, NoteAttachmentSelection.maximumCount - (model.source(id: noteID)?.attachedSourceIDs?.count ?? 0))
  }

  private var candidates: [ProjectSource] {
    guard let note = model.source(id: noteID) else { return [] }
    let attached = Set(note.attachedSourceIDs ?? [])
    return model.projectSources.filter {
      $0.id != noteID && !attached.contains($0.id) && $0.projectID == note.projectID
    }
  }

  var body: some View {
    let allCandidates = candidates
    let matches = allCandidates.filter { CollectionSearch.matches(query, fields: [$0.title, $0.summary ?? ""]) }
    NavigationStack {
      List {
        Section {
          Text("\(selection.ids.count)件を選択・あと\(max(0, remainingCapacity - selection.ids.count))件選べます")
            .font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(matches) { source in
        Button {
          selection.toggle(source.id, maximumCount: remainingCapacity)
        } label: {
          HStack(spacing: 12) {
            ProjectSourceRow(source: source)
            Spacer(minLength: 0)
            Image(icon: selection.contains(source.id) ? .checkmarkCircle : .circle, size: 20)
              .foregroundStyle(selection.contains(source.id) ? MemoraPalette.textPrimary : MemoraPalette.textSecondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selection.contains(source.id) && selection.ids.count >= remainingCapacity)
        .accessibilityAddTraits(selection.contains(source.id) ? [.isSelected] : [])
        }
      }
      .overlay {
        if remainingCapacity == 0 {
          ContentUnavailableView("添付は64件までです", icon: .paperclip,
            description: Text("追加するには、ノートから既存の添付を外してください。"))
        } else if matches.isEmpty {
          ContentUnavailableView(allCandidates.isEmpty ? "添付できる資料がありません" : "見つかりません", icon: .doc)
        }
      }
      .searchable(text: $query, prompt: "資料名を検索")
      .navigationTitle("資料を添付")
      .navigationBarTitleDisplayMode(.inline)
      .overlay(alignment: .bottom) {
        if let failure { Text(failure).font(.footnote).foregroundStyle(MemoraPalette.danger).padding() }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("添付", icon: .checkmark) {
            if model.attachProjectSources(selection.ids, toNote: noteID) { dismiss() }
            else { failure = "添付できませんでした。合計64件以内か、資料と保存先が変更されていないか確認してください。" }
          }
          .disabled(selection.isEmpty || selection.ids.count > remainingCapacity)
        }
      }
    }
  }
}
