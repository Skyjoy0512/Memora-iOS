import SwiftUI

/// Corrects a journal entry's title, text, and time. Changing the time moves the
/// entry to that day in the journal.
struct LifeLogEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var cancelsEditing = false
  @State private var editorCompleted = false
  var entry: LifeLogEntry
  @State private var title: String
  @State private var summary: String
  @State private var createdAt: Date
  @State private var locationName: String
  @State private var place: JournalPlace?
  @State private var personIDs: Set<UUID>
  @State private var saveError = false

  init(entry: LifeLogEntry) {
    self.entry = entry
    _title = State(initialValue: entry.title)
    _summary = State(initialValue: entry.summary)
    _personIDs = State(initialValue: Set(entry.personIDs))
    _createdAt = State(initialValue: entry.occurredAt)
    _locationName = State(initialValue: entry.locationName ?? "")
    _place = State(initialValue: JournalPlace(name: entry.locationName ?? entry.title,
      latitude: entry.latitude, longitude: entry.longitude))
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section("内容") {
          TextField("タイトル", text: $title, axis: .vertical)
            .accessibilityLabel("タイトル")
          TextField("本文", text: $summary, axis: .vertical)
            .lineLimit(3...8)
            .accessibilityLabel("本文")
          InlineLinkSummaryView(text: $summary)
        }

        Section {
          DatePicker("日時", selection: $createdAt)
        } header: {
          Text("日時")
        } footer: {
          Text("日時を変えると、ジャーナルのその日の位置へ移動します。")
        }
        if entry.kind == .location || entry.kind == .event {
          JournalPlaceField(name: $locationName, place: $place)
        }
        if AIJournalPrivacy.allowsReading(kind: entry.kind, origin: entry.origin) {
          JournalPeopleFields(people: model.people, retainedIDs: Set(entry.personIDs), selection: $personIDs)
        }
      }
      .navigationTitle("記録を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { cancelsEditing = true }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            let saved = model.handlingPersistenceFailureLocally { model.updateLifeLogEntry(
              entry.id,
              title: title,
              summary: summary,
              createdAt: createdAt,
              locationName: locationName,
              place: place,
              personIDs: personIDs
            ) }
            if saved { editorCompleted = true; dismiss() } else { saveError = true }
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("保存できませんでした", isPresented: $saveError) {
        Button("閉じる", role: .cancel) {}
      } message: {
        Text("記録と人物の登録状態を確認して、もう一度お試しください。入力内容はこの画面に残っています。")
      }
    }
    .protectsEditorDraft(key: "editor.\(model.currentTeamID ?? "personal").journal.\(entry.id)",
      fields: [
        EditorDraftField("title", $title),
        EditorDraftField("summary", $summary),
        EditorDraftField("date", $createdAt),
        EditorDraftField("location", $locationName),
        EditorDraftField("place", $place),
        EditorDraftField("people", Binding(get: { personIDs.sorted { $0.uuidString < $1.uuidString } }, set: { personIDs = Set($0) }))
      ], cancels: $cancelsEditing, completed: editorCompleted)
    .presentationDetents([.medium, .large])
  }
}
