import SwiftUI
import UniformTypeIdentifiers

struct VideoTranscriptImportSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var source: ProjectSource
  var onSaved: (UUID) -> Void
  @State private var text = ""
  @State private var context: LocalImportContext?
  @State private var isImporting = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var isDraftReady = false
  @State private var captions = YouTubeCaptionService.shared
  private var draftKey: String { "video.transcript.\(source.id)" }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          Text(source.title).font(.headline)
          Button("動画・字幕ファイルを選択", icon: .paperclip) { isImporting = true }
            .frame(minHeight: 44)
        } footer: {
          Text("お持ちの動画・音声、SRT・VTT・テキスト字幕を追加できます。YouTubeから動画をダウンロードすることはありません。")
        }
        Section {
          DisclosureGroup("所有する動画の字幕を取得") {
            if captions.isConnected {
              Button("字幕を再取得") {
                isSaving = true
                Task {
                  defer { isSaving = false }
                  await model.prepareAuthorizedYouTubeCaptions(source.id, retry: true)
                  if model.source(id: source.id)?.canProvideText == true { onSaved(source.id); dismiss() }
                  else { errorMessage = model.source(id: source.id)?.errorInformation }
                }
              }
              Button("YouTubeの接続を解除", role: .destructive) { captions.disconnect() }
            } else {
              Button("YouTubeに接続") {
                Task {
                  do {
                    try await captions.connect()
                    guard context?.isCurrent(in: model) == true else { return }
                    await model.prepareAuthorizedYouTubeCaptions(source.id, retry: true)
                    if model.source(id: source.id)?.canProvideText == true { onSaved(source.id); dismiss() }
                    else { errorMessage = model.source(id: source.id)?.errorInformation }
                  } catch { errorMessage = error.localizedDescription }
                }
              }.disabled(!captions.isConfigured || captions.isWorking)
            }
            Text(captions.isConfigured
              ? "Googleの許可画面を確認してください。字幕の取得には動画の編集権限が必要です。Memoraは動画の変更・公開を行いません。"
              : "このビルドではYouTubeへの接続を利用できません。上のファイル追加をご利用ください。")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        Section {
          DisclosureGroup("字幕を直接貼り付ける") {
            TextEditor(text: $text).frame(minHeight: 220)
              .accessibilityLabel("動画の字幕・文字起こし")
              .accessibilityIdentifier("video.transcript")
            Button("追加") {
              save { try await model.importSourceTranscript(text, source: source, context: context) }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > VideoTranscript.maximumCharacters)
            .accessibilityIdentifier("video.saveTranscript")
          }
        }
        if let errorMessage { Section { Text(errorMessage).foregroundStyle(MemoraPalette.danger) } }
        if isSaving { Section { ProgressView("準備しています…") } }
      }
      .disabled(isSaving || !isDraftReady || context?.isCurrent(in: model) != true)
      .navigationTitle("字幕・動画を追加").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("閉じる", icon: .xmark) { dismiss() } }
      }
      .onAppear {
        guard !isDraftReady else { return }
        do {
          text = try DraftStore.readAll([draftKey])[draftKey] ?? ""
          context = LocalImportContext(projectID: source.projectID, in: model)
          isDraftReady = true
        } catch { model.persistenceFailureMessage = error.localizedDescription }
      }
      .onChange(of: text) { _, value in
        if isDraftReady, context?.isCurrent(in: model) == true { DraftStore.save(value, key: draftKey) }
      }
      .fileImporter(isPresented: $isImporting,
        allowedContentTypes: [.movie, .audio, .plainText, UTType(filenameExtension: "srt") ?? .data, UTType(filenameExtension: "vtt") ?? .data]) { result in
          switch result {
          case .success(let url): save { try await model.importSourceTranscriptFile(url, source: source, context: context) }
          case .failure(let error): errorMessage = error.localizedDescription
          }
        }
    }
  }

  private func save(_ operation: @escaping @MainActor () async throws -> UUID?) {
    guard !isSaving, isDraftReady, context?.isCurrent(in: model) == true else { return }
    isSaving = true; errorMessage = nil
    Task { @MainActor in
      defer { isSaving = false }
      do {
        guard let id = try await operation() else { errorMessage = "保存先の状態が変わりました。開き直して再試行してください。"; return }
        DraftStore.clear(draftKey)
        onSaved(id); dismiss()
      } catch { errorMessage = error.localizedDescription }
    }
  }
}
