import SwiftUI
import QuickLook

struct ProjectSourceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var sourceID: UUID
  var initialExcerpt: String? = nil
  @State private var previewURL: URL?
  @State private var isDeleting = false
  @State private var isDetaching = false
  @State private var isEditing = false
  @State private var isEditingPrivacy = false
  @State private var isAsking = false
  @State private var isAddingVideoTranscript = false
  @State private var isAttachingSources = false
  @State private var isChoosingSummaryOptions = false
  @State private var sourceActionFailure: String?
  @State private var partitionRequest: PDFSourcePartitionRequest?
  @State private var showsOriginal = false
  @State private var textLoader = ProjectSourceTextLoader()
  @State private var textRetry = 0
  @Namespace private var attachmentZoom

  var body: some View {
    if let source = model.source(id: sourceID) {
      let snapshot = textLoader.snapshot
      let extracted = snapshot.value(for: sourceID) ?? []
      let request = ProjectSourceTextRequest(sourceID: sourceID, reference: source.extractedTextReference, retry: textRetry)
      let sourceIsPreparing = isPreparing(source)
      let cannotChange = sourceIsPreparing || model.isRestoring || model.isStoreProtected
      let previousSummaries = self.previousSummaries(for: source)
      let revisions = source.revisions ?? []
      let availabilityMessage = source.processingStatus == .ready || source.kind == .youtube ? nonempty(source.availabilityNotice) : nil
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
              Text(source.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                .memoraTextReveal()
              Text(metadataDescription(for: source)).font(.caption).foregroundStyle(.secondary)
            }
            if let sourceActionFailure { Text(sourceActionFailure).font(.footnote).foregroundStyle(.secondary) }
            if sourceIsPreparing {
              ProgressView("準備しています…").font(.subheadline)
            }
            if let page = source.resumePage, source.kind == .pdf {
              Button("ページ\(page)から読み取りを続ける", icon: .arrowClockwise) {
                model.resumeProjectSource(sourceID)
              }.frame(minHeight: 44).disabled(cannotChange)
            } else if source.kind == .pdf, !(source.ocrFailedPages ?? []).isEmpty, source.canProvideText {
              Button("画像内の文字を再読み取り", icon: .arrowClockwise) {
                model.resumeProjectSource(sourceID)
              }.frame(minHeight: 44).disabled(cannotChange)
            }
            if let summary = source.summary, !summary.isEmpty {
              if source.summaryTextReference != source.extractedTextReference {
                Text("以前の原文から作成した要約です").font(.caption).foregroundStyle(.secondary)
              }
              MarkdownDocumentView(markdown: summary, isLazy: true)
                .memoraTextReveal()
            }
            if let failure = summaryFailure(for: source) {
              VStack(alignment: .leading, spacing: 8) {
                Text(failure).font(.footnote).foregroundStyle(.secondary)
                if source.canProvideText {
                  Button("要約を再試行", icon: .arrowClockwise) {
                    guard canStartSourceChange() else { return }
                    Task { await model.summarizeProjectSource(sourceID, retry: true) }
                  }.frame(minHeight: 44).disabled(cannotChange)
                }
              }
            }
            if source.kind == .note, !model.attachedSources(of: source).isEmpty {
              attachedSourcesSection(source)
            }
            if source.canProvideText {
              Button("この資料について聞く", icon: .sparkles) { isAsking = true }
                .buttonStyle(.plain).font(.subheadline)
                .foregroundStyle(MemoraPalette.textPrimary)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("source.askAI")
            }
            if source.kind == .youtube, !source.canProvideText {
              Text("字幕がまだありません。お持ちの動画・字幕ファイルの追加や、権限のあるYouTubeアカウントとの接続を試せます。")
                .font(.subheadline).foregroundStyle(.secondary)
              Button("動画・字幕ファイルを追加", icon: .paperclip) {
                guard canStartSourceChange() else { return }
                isAddingVideoTranscript = true
              }
                .frame(minHeight: 44).disabled(cannotChange)
              if let id = source.metadata?["videoTranscriptMeetingID"].flatMap(UUID.init(uuidString:)), model.meeting(id: id) != nil {
                NavigationLink("以前の字幕・要約を開く", value: LibraryRoute.meeting(id)).frame(minHeight: 44)
              }
            }
            if source.processingStatus == .failed || source.processingStatus == .unavailable,
               source.kind != .youtube, source.resumePage == nil {
              Text(nonempty(source.errorInformation) ?? "内容を読み取れませんでした。元の資料を確認するか、もう一度お試しください。")
                .font(.footnote).foregroundStyle(.secondary)
              Button("再試行", icon: .arrowClockwise) {
                guard canStartSourceChange() else { return }
                Task { await model.prepareProjectSource(sourceID) }
              }.frame(minHeight: 44).disabled(cannotChange)
            }
            if source.canProvideText || !extracted.isEmpty {
              DisclosureGroup(source.kind == .audio || source.kind == .video || source.kind == .youtube ? "文字起こし・字幕" : "原文", isExpanded: $showsOriginal) {
                MemoraLoadingContainer(state: snapshot.state(for: sourceID), label: "読み込んでいます…",
                  activityID: snapshot.activityID, failure: snapshot.key == sourceID ? snapshot.failure : nil,
                  retry: { textRetry += 1 }, cancel: { textLoader.stop() }) {
                    LazyVStack(alignment: .leading, spacing: 20) {
                      ForEach(Array(extracted.enumerated()), id: \.offset) { index, block in
                        VStack(alignment: .leading, spacing: 6) {
                          if let page = block.page, source.kind == .pdf {
                            NavigationLink("ページ \(page)", value: LibraryRoute.projectPDF(sourceID, page))
                              .font(.footnote).frame(minHeight: 44)
                          }
                          if let time = ProjectCitationLocation.playbackTime(block.time) {
                            if source.localFileReference != nil {
                              NavigationLink(MemoraFormat.duration(time)) { SourceMediaPlayerView(sourceID: sourceID, start: time) }
                                .font(.footnote).frame(minHeight: 44)
                            } else if let original = source.originalURL, var parts = URLComponents(url: original, resolvingAgainstBaseURL: false) {
                              let _ = parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "t" } + [URLQueryItem(name: "t", value: String(Int(time)))]
                              if let url = parts.url { Link(MemoraFormat.duration(time), destination: url).font(.footnote).frame(minHeight: 44) }
                            }
                          }
                          Text(block.text).memoraReadingText().textSelection(.enabled)
                        }.id("source.text.\(index)")
                      }
                    }
                    .memoraTextReveal()
                  }
              }.id("source.original")
            }
            if availabilityMessage != nil || !previousSummaries.isEmpty || !revisions.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Divider()
                if let availabilityMessage {
                  DisclosureGroup("資料について") { Text(availabilityMessage).font(.footnote).foregroundStyle(.secondary) }
                }
                if !previousSummaries.isEmpty {
                  DisclosureGroup("以前の要約") {
                    ForEach(Array(previousSummaries.enumerated()), id: \.offset) { index, summary in
                      DisclosureGroup("保存済みの要約 \(index + 1)") {
                        MarkdownDocumentView(markdown: summary, isLazy: true)
                      }
                    }
                  }
                }
                if !revisions.isEmpty {
                  DisclosureGroup("原文の更新履歴") {
                    ForEach(Array(revisions.enumerated()), id: \.offset) { _, revision in
                      VStack(alignment: .leading, spacing: 8) {
                        Text(revision.acquiredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        if let summary = nonempty(revision.summary) { MarkdownDocumentView(markdown: summary, isLazy: true) }
                      }
                    }
                  }
                }
              }
              .font(.subheadline).tint(MemoraPalette.textSecondary)
            }
            if let url = source.originalURL { Link("元のページを開く", destination: url).frame(minHeight: 44) }
            if let name = source.localFileReference, let file = ProjectSourceFiles.resolve(name) {
              if source.kind == .pdf {
                NavigationLink("PDFを開く", value: LibraryRoute.projectPDF(sourceID, 1)).frame(minHeight: 44)
              } else if source.kind == .audio || source.kind == .video || source.kind == .youtube {
                NavigationLink("再生") { SourceMediaPlayerView(sourceID: sourceID) }.frame(minHeight: 44)
              } else {
                Button("元のファイルを開く", icon: .doc) { previewURL = file }.frame(minHeight: 44)
              }
            }
          }
          .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
          .padding(ProjectLayout.horizontalInset)
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: extracted) { _, blocks in
          guard let initialExcerpt, let index = blocks.firstIndex(where: { $0.text.contains(initialExcerpt) }) else { return }
          showsOriginal = true
          // The disclosure's header already exists before its text is expanded.
          proxy.scrollTo("source.original", anchor: .top)
          if showsOriginal { proxy.scrollTo("source.text.\(index)", anchor: .top) }
        }
        .onChange(of: showsOriginal) { _, expanded in
          guard expanded, let initialExcerpt,
                let index = extracted.firstIndex(where: { $0.text.contains(initialExcerpt) }) else { return }
          proxy.scrollTo("source.text.\(index)", anchor: .top)
        }
      }
      .background(MemoraPalette.background)
      .navigationTitle("資料").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            if source.kind == .note {
              Button("メモを編集", icon: .pencil) { isEditing = true }.disabled(extracted.isEmpty)
              Button("資料を添付", icon: .paperclip) { isAttachingSources = true }
            }
            if source.canProvideText {
              Button("要約を作り直す", icon: .sparkles) {
                guard canStartSourceChange() else { return }
                Task { await model.summarizeProjectSource(sourceID, retry: true) }
              }
              Button("要約の設定", icon: .sliderHorizontal3) {
                guard canStartSourceChange() else { return }
                isChoosingSummaryOptions = true
              }
            }
            if source.originalURL != nil, source.kind == .web || source.kind == .pdf {
              Button("原文を更新", icon: .arrowClockwise) {
                guard canStartSourceChange() else { return }
                Task { await model.acquireRemoteSource(sourceID, refresh: true); await model.summarizeProjectSource(sourceID) }
              }
            }
            if source.kind == .pdf, source.localFileReference != nil {
              Button("原文を読み直す", icon: .arrowClockwise) {
                guard canStartSourceChange() else { return }
                sourceActionFailure = nil
                if !model.rereadProjectPDFSource(sourceID) {
                  sourceActionFailure = "原文を読み直せませんでした。保存したPDFと保存先を確認して、もう一度お試しください。"
                }
              }
              Button("PDFを分けて追加", icon: .docText) {
                guard canStartSourceChange(), let current = model.source(id: sourceID), current.kind == .pdf,
                      let reference = current.localFileReference, let file = ProjectSourceFiles.resolve(reference),
                      let context = LocalImportContext(projectID: current.projectID, in: model) else { return }
                partitionRequest = PDFSourcePartitionRequest(url: file, context: context, originalSource: current)
              }
            }
            Button("プライバシー", icon: .lock) { isEditingPrivacy = true }
            if source.projectID != nil { Button("プロジェクトから外す", icon: .folder) { isDetaching = true } }
            Button("資料を削除", icon: .trash, role: .destructive) { isDeleting = true }
          } label: { ToolbarActionLabel("その他", icon: .ellipsis) }
          .disabled(cannotChange)
        }
      }
      .quickLookPreview($previewURL)
      .task(id: sourceID) {
        if model.source(id: sourceID)?.processingStatus == .pending { await model.prepareProjectSource(sourceID) }
      }
      .task(id: request) {
        await textLoader.load(request) { model.source(id: sourceID)?.extractedTextReference == request.reference }
        if source.summary == nil || initialExcerpt != nil { showsOriginal = true }
      }
      .sheet(isPresented: $isAddingVideoTranscript) { VideoTranscriptImportSheet(source: source) { _ in } }
      .sheet(isPresented: $isAttachingSources) { ProjectNoteAttachSheet(noteID: sourceID) }
      .sheet(isPresented: $isChoosingSummaryOptions) { SourceSummaryOptionsSheet(sourceID: sourceID) }
      .sheet(item: $partitionRequest) { request in PDFSourcePartitionSheet(request: request) }
      .sheet(isPresented: $isAsking) { AIQuestionView(request: AIQuestionRequest(question: "", scope: .global, sourceID: sourceID)) }
      .sheet(isPresented: $isEditing) { ProjectNoteEditSheet(source: source, text: extracted.map(\.text).joined(separator: "\n")) }
      .sheet(isPresented: $isEditingPrivacy) { ProjectSourcePrivacySheet(source: source) }
      .confirmationDialog("資料を削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) { if model.deleteProjectSource(sourceID) { dismiss() } }
      } message: { Text("保存したコピーと要約を削除します。元のファイルや他の記録は削除しません。") }
      .confirmationDialog("プロジェクトから外しますか？", isPresented: $isDetaching, titleVisibility: .visible) {
        Button("外す") { model.detachProjectSource(sourceID) }
      } message: { Text("資料はライブラリに残ります。") }
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    } else { ContentUnavailableView("資料が見つかりません", icon: .docQuestionmark) }
  }

  private func isPreparing(_ source: ProjectSource) -> Bool {
    model.projectSourceProcessingIDs.contains(sourceID) ||
      source.processingStatus == .pending || source.processingStatus == .processing || source.summaryStatus == .processing
  }

  private func canStartSourceChange() -> Bool {
    guard let current = model.source(id: sourceID),
          !model.isRestoring, !model.isStoreProtected,
          model.sourcePreparationJobs[sourceID] == nil else { return false }
    return !isPreparing(current)
  }

  private func summaryFailure(for source: ProjectSource) -> String? {
    if let message = nonempty(source.summaryError) { return message }
    guard source.summaryStatus == .failed || source.summaryStatus == .unavailable else { return nil }
    return source.canProvideText
      ? "要約を作成できませんでした。原文は引き続き確認できます。"
      : "要約を作成できませんでした。資料の内容を取得してから、もう一度お試しください。"
  }

  private func attachedSourcesSection(_ source: ProjectSource) -> some View {
    let attachments = model.attachedSources(of: source)
    return VStack(alignment: .leading, spacing: 10) {
      Text("添付資料").font(MemoraTypography.sectionHeading)
      Text("添付資料はそれぞれ独立して検索・引用されます。").font(.caption).foregroundStyle(.secondary)
      ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
        HStack(spacing: 8) {
          NavigationLink {
            if reduceMotion {
              ProjectSourceDetailView(sourceID: attachment.id)
            } else {
              ProjectSourceDetailView(sourceID: attachment.id)
                .navigationTransition(.zoom(sourceID: attachment.id, in: attachmentZoom))
            }
          } label: {
            ProjectSourceRow(source: attachment)
              .matchedTransitionSource(id: attachment.id, in: attachmentZoom)
          }
          .buttonStyle(.plain)
          Menu {
            Button("上へ移動", icon: .arrowUp) {
              moveAttachment(attachment.id, index: index, by: -1)
            }.disabled(index == 0)
            Button("下へ移動", icon: .arrowDown) {
              moveAttachment(attachment.id, index: index, by: 1)
            }.disabled(index == attachments.count - 1)
            Divider()
            Button("添付を解除", icon: .xmark, role: .destructive) {
              if !model.removeAttachedSource(attachment.id, fromNote: source.id) {
                sourceActionFailure = "添付を解除できませんでした。空き容量を確認してください。"
              }
            }
          } label: {
            Image(icon: .ellipsis, size: MemoraIconMetrics.accessory)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .accessibilityLabel("添付の操作")
        }
      }
    }
  }

  private func moveAttachment(_ id: UUID, index: Int, by offset: Int) {
    if !model.moveAttachedSource(id, inNote: sourceID, offset: offset) {
      sourceActionFailure = "添付資料の順序を変更できませんでした。空き容量を確認してください。"
    }
  }

  private func previousSummaries(for source: ProjectSource) -> [String] {
    // Original revisions already retain their own summaries; don't show those twice.
    var seen = Set(([source.summary] + (source.revisions ?? []).map(\.summary)).compactMap(nonempty))
    return Array((source.summaryHistory ?? []).reversed().compactMap { value in
      guard let summary = nonempty(value), seen.insert(summary).inserted else { return nil }
      return summary
    }.prefix(3))
  }

  private func nonempty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
  }

  private func metadataDescription(for source: ProjectSource) -> String {
    var parts = [source.kindLabel]
    if let author = nonempty(source.metadata?["webAuthor"] ?? source.metadata?["youtubeAuthor"]) { parts.append(author) }
    if let date = source.acquiredAt ?? source.webFetchedAt {
      parts.append("取得：" + date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))))
    }
    return parts.joined(separator: " · ")
  }
}
