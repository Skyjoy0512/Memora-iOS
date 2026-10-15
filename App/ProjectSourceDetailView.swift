import SwiftUI
import QuickLook

struct ProjectSourceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var sourceID: UUID
  @State private var previewURL: URL?
  @State private var isDeleting = false
  @State private var isDetaching = false
  @State private var isEditing = false
  @State private var isEditingPrivacy = false
  @State private var extracted: [ProjectSourceText] = []
  @State private var textFailure: String?
  @State private var webFetchRequest: UUID?

  var body: some View {
    if let source = model.source(id: sourceID) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(source.title).font(.title2.weight(.semibold)).textSelection(.enabled)
          Text("\(source.kindLabel) · \(source.statusLabel)").font(.footnote).foregroundStyle(.secondary)
          if let date = source.webFetchedAt {
            Text("取得: \(date.formatted(date: .abbreviated, time: .shortened))")
              .font(.footnote).foregroundStyle(.secondary)
          }
          if let author = source.metadata?["youtubeAuthor"], !author.isEmpty {
            Text(author).font(.footnote).foregroundStyle(.secondary)
          }
          if let failure = source.metadata?["thumbnailError"] {
            Text(failure).font(.subheadline).foregroundStyle(.secondary)
          }
          if let message = source.availabilityNotice {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
          }
          if let textFailure { Text(textFailure).font(.subheadline).foregroundStyle(.secondary) }
          if source.kind == .web {
            if webFetchRequest != nil {
              ProgressView("本文を取得中…").font(.subheadline)
              Button("取得を停止") { webFetchRequest = nil }.frame(minHeight: 44)
                .tint(MemoraPalette.textPrimary)
            } else {
              Button(source.canProvideText ? "本文を更新" : "Web本文を取得") { webFetchRequest = UUID() }
                .frame(minHeight: 44)
                .tint(MemoraPalette.textPrimary)
                .disabled(model.projectSourceProcessingIDs.contains(sourceID) || model.isRestoring || model.isStoreProtected)
            }
          }
          ForEach(Array(extracted.enumerated()), id: \.offset) { _, block in
            if let page = block.page { Text("ページ \(page)").font(.footnote).foregroundStyle(.secondary) }
            Text(block.text).font(.body).lineSpacing(4).textSelection(.enabled)
          }
          if let url = source.originalURL {
            Link("元のページを開く", destination: url).font(.body)
          }
          if let reference = source.localFileReference, let file = ProjectSourceFiles.resolve(reference) {
            if source.kind == .pdf {
              NavigationLink("PDFを表示", value: LibraryRoute.projectPDF(sourceID, 1)).frame(minHeight: 44)
            } else {
              Button("ファイルを表示", icon: .doc) { previewURL = file }.frame(minHeight: 44)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(ProjectLayout.horizontalInset)
      }
      .background(MemoraPalette.background)
      .navigationTitle("").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            if source.kind == .note {
              Button("メモを編集", icon: .pencil) { isEditing = true }
                .disabled(extracted.isEmpty || textFailure != nil)
            }
            if (source.localFileReference != nil || (source.kind == .youtube && source.metadata?["youtubeTitle"] == nil)) && source.processingStatus != .ready {
              Button("解析を再試行", icon: .arrowClockwise) {
                Task { await model.prepareProjectSource(sourceID) }
              }.disabled(model.projectSourceProcessingIDs.contains(sourceID))
            }
            if source.kind == .youtube, source.metadata?["youtubeTitle"] != nil, source.thumbnailReference == nil {
              Button("サムネイルを取得", icon: .photo) { Task { await model.prepareProjectSource(sourceID) } }
                .disabled(model.projectSourceProcessingIDs.contains(sourceID))
            }
            Button("プライバシー", icon: .lock) { isEditingPrivacy = true }
            if source.projectID != nil {
              Button("プロジェクトから外す", icon: .folder) { isDetaching = true }
            }
            Button("ソースを削除", icon: .trash, role: .destructive) { isDeleting = true }
          } label: { ToolbarActionLabel("その他", icon: .ellipsis) }
        }
      }
      .quickLookPreview($previewURL)
      .task(id: webFetchRequest) {
        guard let request = webFetchRequest else { return }
        await model.fetchProjectWebSource(sourceID)
        if webFetchRequest == request { webFetchRequest = nil }
      }
      .task(id: sourceID) {
        if source.processingStatus == .pending || source.processingStatus == .processing ||
           (source.kind == .youtube && source.thumbnailReference == nil) {
          await model.prepareProjectSource(sourceID)
        }
      }
      .task(id: source.extractedTextReference) {
        extracted = []; textFailure = nil
        guard let name = source.extractedTextReference else { return }
        do { extracted = try await Task.detached { try ProjectSourceTextReader.read(name) }.value }
        catch { textFailure = "保存された本文を読み込めませんでした。" }
      }
      .sheet(isPresented: $isEditing) {
        ProjectNoteEditSheet(source: source, text: extracted.map(\.text).joined(separator: "\n"))
      }
      .sheet(isPresented: $isEditingPrivacy) { ProjectSourcePrivacySheet(source: source) }
      .confirmationDialog("ソースを削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          if model.deleteProjectSource(sourceID) { dismiss() }
        }
      } message: { Text("保存したコピーと解析結果を削除します。元のファイルや他の録音・資料は削除しません。") }
      .confirmationDialog("プロジェクトから外しますか？", isPresented: $isDetaching, titleVisibility: .visible) {
        Button("外す") { model.detachProjectSource(sourceID) }
      } message: { Text("ソースはライブラリに残ります。") }
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    } else {
      ContentUnavailableView("ソースが見つかりません", icon: .docQuestionmark)
    }
  }
}
