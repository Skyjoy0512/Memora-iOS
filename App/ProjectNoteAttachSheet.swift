import SwiftUI

/// Links existing sources from the note's own save destination to the note.
/// Nothing is copied, moved or deleted; the note only gains references.
struct ProjectNoteAttachSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var noteID: UUID
  @State private var selection = NoteAttachmentSelection()
  @State private var failure: String?

  private var candidates: [ProjectSource] {
    guard let note = model.source(id: noteID) else { return [] }
    let attached = Set(note.attachedSourceIDs ?? [])
    return model.projectSources.filter {
      $0.id != noteID && !attached.contains($0.id) && $0.projectID == note.projectID
    }
  }

  var body: some View {
    NavigationStack {
      List(candidates) { source in
        Button {
          selection.toggle(source.id)
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
        .accessibilityAddTraits(selection.contains(source.id) ? [.isSelected] : [])
      }
      .overlay {
        if candidates.isEmpty {
          ContentUnavailableView("添付できる資料がありません", icon: .doc)
        }
      }
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
            else { failure = "添付できませんでした。空き容量を確認してください。" }
          }
          .disabled(selection.isEmpty)
        }
      }
    }
  }
}
