import SwiftUI

struct VideoTranscriptImportSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var source: ProjectSource
  var onSaved: (UUID) -> Void
  @State private var text = ""
  @State private var context: LocalImportContext?
  @State private var savedMeetingID: UUID?
  @State private var errorMessage: String?
  @FocusState private var isEditing: Bool
  private var draftKey: String { "video.transcript.\(source.id)" }

  var body: some View {
    if let savedMeetingID {
      SummaryGenerationSheet(meetingID: savedMeetingID)
    } else {
      NavigationStack {
        MemoraForm {
          Section {
            Text(source.title).font(.headline)

          }
          Section {
            PasteButton(payloadType: String.self) { values in
              let pasted = values.joined(separator: "\n")
              text = text.isEmpty ? pasted : text + "\n" + pasted
            }
            .accessibilityLabel("字幕を貼り付け")
            TextEditor(text: $text)
              .frame(minHeight: 240)
              .focused($isEditing)
              .accessibilityLabel("動画の字幕・文字起こし")
              .accessibilityIdentifier("video.transcript")
          } header: {
            Text("字幕・文字起こし")
          }
          if text.count > VideoTranscript.maximumCharacters {
            Text("20万文字以内にしてください").font(.footnote).foregroundStyle(.red)
          }
          if let errorMessage {
            Section { Text(errorMessage).foregroundStyle(.red) }
          }
          Section {
            Button("保存して次へ", icon: .sparkles) {
              guard let id = model.handlingPersistenceFailureLocally({
                model.importVideoTranscript(text, source: source, context: context)
              }) else {
                errorMessage = "保存できませんでした。保存先やプライバシー設定が変わっていないか確認し、開き直してください。"
                return
              }
              DraftStore.clear(draftKey)
              isEditing = false
              onSaved(id)
              savedMeetingID = id
            }
            .accessibilityIdentifier("video.saveTranscript")
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || text.count > VideoTranscript.maximumCharacters || context?.isCurrent(in: model) != true)
          }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("字幕を追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
          }
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("キーボードを閉じる", icon: .chevronDown) { isEditing = false }.labelStyle(.iconOnly)
          }
        }
        .onAppear {
          guard context == nil else { return }
          context = LocalImportContext(projectID: source.projectID, in: model)
          text = DraftStore.load(draftKey) ?? ""
        }
        .onChange(of: text) { _, value in
          guard context?.isCurrent(in: model) == true else { return }
          DraftStore.save(value, key: draftKey)
        }
      }
    }
  }
}
