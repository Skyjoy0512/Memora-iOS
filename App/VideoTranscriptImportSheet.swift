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
            Text("YouTubeの字幕や、用意した文字起こしを貼り付けてください。貼り付けた範囲を動画用の形式で要約します。")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          Section {
            TextEditor(text: $text)
              .frame(minHeight: 240)
              .focused($isEditing)
              .accessibilityLabel("動画の字幕・文字起こし")
              .accessibilityIdentifier("video.transcript")
          } header: {
            Text("字幕・文字起こし")
          } footer: {
            Text("20万文字まで。動画の音声・字幕は自動取得しません。次の画面でAIと送信先を確認し、「生成」を押すと要約します。")
          }
          if let errorMessage {
            Section { Text(errorMessage).foregroundStyle(.red) }
          }
          Section {
            Button("保存して要約設定へ", icon: .sparkles) {
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
        .navigationTitle("字幕から要約")
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
