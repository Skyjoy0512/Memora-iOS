import SwiftUI

struct MeetingHighlightsEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID
  @State private var points = ""
  @State private var decisions = ""
  @State private var questions = ""
  @State private var original: Meeting?
  @State private var context: LocalImportContext?
  @State private var isSaving = false
  @State private var failure: String?
  private var draftPrefix: String { "meeting.\(meetingID).highlights" }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section("要点") { TextEditor(text: $points).frame(minHeight: 110).accessibilityLabel("要点") }
        Section("決定事項") { TextEditor(text: $decisions).frame(minHeight: 110).accessibilityLabel("決定事項") }
        Section("未決事項") { TextEditor(text: $questions).frame(minHeight: 110).accessibilityLabel("未決事項") }
        if let failure { Section { Text(failure).foregroundStyle(.red) } }
      }
      .scrollDismissesKeyboard(.interactively)
      .disabled(isSaving)
      .navigationTitle("要点・決定事項")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) { save() }
            .disabled(isSaving || context?.isCurrent(in: model) != true || model.processing.isActive(meetingID))
            .accessibilityIdentifier("meeting.highlights.save")
        }
      }
      .interactiveDismissDisabled(isSaving)
      .onAppear {
        guard original == nil, let meeting = model.meeting(id: meetingID) else { return }
        context = LocalImportContext(in: model)
        original = meeting
        points = DraftStore.load(draftPrefix + ".points") ?? meeting.keyPoints.joined(separator: "\n")
        decisions = DraftStore.load(draftPrefix + ".decisions") ?? meeting.decisions.joined(separator: "\n")
        questions = DraftStore.load(draftPrefix + ".questions") ?? meeting.openQuestions.joined(separator: "\n")
      }
      .onChange(of: points) { _, value in saveDraft(value, field: "points") }
      .onChange(of: decisions) { _, value in saveDraft(value, field: "decisions") }
      .onChange(of: questions) { _, value in saveDraft(value, field: "questions") }
    }
  }

  private func saveDraft(_ value: String, field: String) {
    guard context?.isCurrent(in: model) == true else { return }
    DraftStore.save(value, key: draftPrefix + "." + field)
  }

  private func save() {
    guard !isSaving else { return }
    isSaving = true
    Task { @MainActor in
      defer { isSaving = false }
      guard context?.isCurrent(in: model) == true, !model.processing.isActive(meetingID),
            let current = model.meeting(id: meetingID), let original,
            current.keyPoints == original.keyPoints, current.decisions == original.decisions,
            current.openQuestions == original.openQuestions else {
        failure = "記録が更新されました。開き直して確認してください。"
        return
      }
      let keyPoints = lines(points), newDecisions = lines(decisions), openQuestions = lines(questions)
      let saved = await model.commitMeetingChange(meetingID) {
        $0.keyPoints = keyPoints
        $0.decisions = newDecisions
        $0.openQuestions = openQuestions
      }
      guard saved else { failure = "保存できませんでした。もう一度お試しください。"; return }
      for field in ["points", "decisions", "questions"] { DraftStore.clear(draftPrefix + "." + field) }
      dismiss()
    }
  }

  private func lines(_ value: String) -> [String] {
    value.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }
}
