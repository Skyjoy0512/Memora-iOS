import QuickLook
import SwiftUI

struct ConversationAttachmentView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var file: AIAttachment.File
  var initialExcerpt: String? = nil
  @State private var content: ProjectSourceExtractionResult?
  @State private var readingFailure: String?
  @State private var readAttempt = 0
  @State private var workspaceGeneration: UUID?
  @State private var previewURL: URL?
  @State private var savedID: UUID?
  @State private var isSaving = false
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      Group {
        if let workspaceGeneration, workspaceGeneration != model.aiWorkspaceGeneration {
          ContentUnavailableView("資料を開き直してください", icon: .docQuestionmark,
            description: Text("保存先が変わりました。この会話からもう一度開いてください。"))
        } else {
          attachmentContent
        }
      }
      .navigationTitle("添付資料").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("閉じる", icon: .xmark) { dismiss() } } }
      .quickLookPreview($previewURL)
      .task(id: ReadRequest(file: file, attempt: readAttempt)) { await loadContent() }
      .onChange(of: model.currentTeamID) { _, _ in dismiss() }
      .onChange(of: model.isRestoring) { _, restoring in if restoring { dismiss() } }
    }
  }

  private var attachmentContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          Text(file.name).font(.title2.weight(.semibold)).textSelection(.enabled)
          if let url = file.originalURL { Link("元のページを開く", destination: url).frame(minHeight: 44) }
          if kind == .pdf {
            NavigationLink("PDFを開く") { LocalSourcePDFView(url: file.url).navigationTitle(file.name).navigationBarTitleDisplayMode(.inline) }
              .frame(minHeight: 44)
          } else if kind == .audio || kind == .video {
            NavigationLink("再生") { LocalSourceMediaPlayerView(url: file.url, title: file.name, start: nil) }
              .frame(minHeight: 44)
          } else if file.url.pathExtension.lowercased() != "memorasource" {
            Button("元のファイルを開く", icon: .doc) { previewURL = file.url }.frame(minHeight: 44)
          }
          saveControls
        if let content {
          if let notice = content.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
          if let page = content.resumePage {
            Button("ページ\(page)から読み取りを続ける", icon: .arrowClockwise) { readAttempt += 1 }.frame(minHeight: 44)
          } else if !content.ocrFailedPages.isEmpty, !content.blocks.isEmpty {
            Button("画像内の文字を再読み取り", icon: .arrowClockwise) { readAttempt += 1 }.frame(minHeight: 44)
          }
            if content.blocks.isEmpty {
              Text("読み取れる本文がありません。元の資料を確認できます。")
                .font(.subheadline).foregroundStyle(.secondary)
              Button("再試行", icon: .arrowClockwise) { readAttempt += 1 }.frame(minHeight: 44)
            } else {
              Text(kind == .audio || kind == .video || content.blocks.contains(where: { $0.time != nil }) ? "文字起こし・字幕" : "原文")
                .font(.headline)
              ForEach(content.blocks.indices, id: \.self) { index in
                originalBlock(content.blocks[index]).id("attachment.text.\(index)")
              }
            }
          } else if let readingFailure {
            Text(readingFailure).font(.footnote).foregroundStyle(.secondary)
            Button("再試行", icon: .arrowClockwise) { readAttempt += 1 }.frame(minHeight: 44)
          } else { ProgressView("読み込んでいます…") }

        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(MemoraSpacing.screen).frame(maxWidth: .infinity)
      }
      .onChange(of: content?.blocks) { _, blocks in
        guard let initialExcerpt, !initialExcerpt.isEmpty,
              let index = blocks?.firstIndex(where: { $0.text.contains(initialExcerpt) }) else { return }
        proxy.scrollTo("attachment.text.\(index)", anchor: .top)
      }
    }
  }

  private var saveControls: some View {
    VStack(alignment: .leading, spacing: 12) {
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
  }

  private var kind: ProjectSource.Kind { SourceIntake.kind(for: file.url) }

  private func originalBlock(_ block: ProjectSourceText) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if let page = block.page {
        if kind == .pdf {
          NavigationLink("ページ \(page)") {
            LocalSourcePDFView(url: file.url, page: page).navigationTitle(file.name).navigationBarTitleDisplayMode(.inline)
          }.font(.footnote).frame(minHeight: 44)
        } else {
          Text("ページ \(page)").font(.footnote).foregroundStyle(.secondary)
        }
      }
      if let time = ProjectCitationLocation.playbackTime(block.time) {
        if kind == .audio || kind == .video {
          NavigationLink(MemoraFormat.duration(time)) {
            LocalSourceMediaPlayerView(url: file.url, title: file.name, start: time)
          }.font(.footnote).frame(minHeight: 44)
        } else if let url = timedOriginalURL(time) {
          Link(MemoraFormat.duration(time), destination: url).font(.footnote).frame(minHeight: 44)
        } else {
          Text(MemoraFormat.duration(time)).font(.footnote).foregroundStyle(.secondary)
        }
      }
      Text(block.text).memoraReadingText().textSelection(.enabled)
    }
  }

  private func timedOriginalURL(_ time: TimeInterval) -> URL? {
    guard let original = file.originalURL,
          let link = try? ProjectSourceURL.normalized(original.absoluteString), link.kind == .youtube,
          var components = URLComponents(url: link.url, resolvingAgainstBaseURL: false) else { return nil }
    components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: String(Int(time)))]
    return components.url
  }

  private func loadContent() async {
    let generation = workspaceGeneration ?? model.aiWorkspaceGeneration
    workspaceGeneration = generation
    guard generation == model.aiWorkspaceGeneration else { return }
    content = nil
    readingFailure = nil
    do {
      let value = try await SourceExtractionCache.shared.extract(file.url, vocabulary: model.transcriptionVocabulary)
      guard !Task.isCancelled, generation == model.aiWorkspaceGeneration else { return }
      content = value
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled, generation == model.aiWorkspaceGeneration else { return }
      readingFailure = error.localizedDescription
    }
  }
}

private struct ReadRequest: Hashable {
  var file: AIAttachment.File
  var attempt: Int
}
