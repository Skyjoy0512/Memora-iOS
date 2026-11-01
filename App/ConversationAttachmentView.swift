import QuickLook
import SwiftUI

struct ConversationAttachmentView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var file: AIAttachment.File
  @State private var content: PreparedAIAttachment?
  @State private var previewURL: URL?
  @State private var savedID: UUID?
  @State private var isSaving = false
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(file.name).font(.title2.weight(.semibold)).textSelection(.enabled)
          if let url = file.originalURL { Link("元のページを開く", destination: url).frame(minHeight: 44) }
          if file.url.pathExtension != "memorasource" {
            Button("元のファイルを開く", icon: .doc) { previewURL = file.url }.frame(minHeight: 44)
          }
          if let content {
            if let text = content.text { Text(text).memoraReadingText().textSelection(.enabled) }
            if let notice = content.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if let failure = content.failure { Text(failure).foregroundStyle(.secondary) }
          } else { ProgressView("読み込んでいます…") }
          if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
          if let savedID {
            NavigationLink("保存した資料を開く") { ProjectSourceDetailView(sourceID: savedID) }.frame(minHeight: 44)
          } else {
            Button("ライブラリに保存", icon: .folder) {
              isSaving = true
              Task {
                defer { isSaving = false }
                do {
                  savedID = try await model.saveConversationFile(file)
                  if savedID == nil { failure = "保存先が変わりました。開き直して再試行してください。" }
                } catch { failure = error.localizedDescription }
              }
            }
            .buttonStyle(MemoraButtonStyle()).disabled(isSaving || model.isRestoring || model.isStoreProtected || model.currentTeamID != nil)
            Text("この会話だけの資料です。保存するとライブラリから検索できます。外部AIへの参照許可は資料ごとに設定できます。")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(MemoraSpacing.screen).frame(maxWidth: .infinity)
      }
      .navigationTitle("添付資料").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("閉じる", icon: .xmark) { dismiss() } } }
      .quickLookPreview($previewURL)
      .task(id: file) {
        let generation = model.aiWorkspaceGeneration
        let value = await AIAttachmentText.prepare(AIAttachment(id: file.id, name: file.name, url: file.url, originalURL: file.originalURL), vocabulary: model.transcriptionVocabulary)
        guard !Task.isCancelled, generation == model.aiWorkspaceGeneration else { return }
        content = value
      }
    }
  }
}
