import PhotosUI
import SwiftUI
import UIKit

struct MeetingDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var meetingID: UUID
  @State private var detailTab: RootTab?
  /// When set, the transcript opens and plays from here — used when an AI answer's
  /// source line is tapped.
  var initialPlaybackStart: TimeInterval?
  /// True when this detail is opened inside a sheet (from an AI answer), where
  /// the root transport is hidden behind it. The bar is then shown at this
  /// screen's own bottom, where nothing else floats.
  var showsLocalPlaybackBar = false
  @State private var selectedSection = MeetingDetailSection.summary
  @State private var isRenaming = false
  @State private var isAddingTask = false
  @State private var isEditingHighlights = false
  @State private var isReviewingExtraction = false
  @State private var isDeleting = false
  @State private var isRemovingAudio = false
  @State private var isSummaryGenerationPresented = false
  @State private var isPrivacyPresented = false
  @State private var isAddingPeople = false
  @State private var isChoosingSpace = false
  @State private var isSharing = false
  @State private var shareItems: [Any] = []
  @State private var statusAlert: StatusAlert?
  @State private var player = AudioPlayerService()
  /// The line the initial time points at, highlighted even without audio.
  @State private var focusedSegmentID: UUID?
  /// Set when this sheet-opened detail has begun playing, so its local bar stays.
  @State private var localPlaybackStarted = false
  /// The initial time is applied once; a later `onAppear` must not seek again.
  @State private var didApplyInitialPlayback = false

  @State private var isSavingToNotion = false
  @State private var pdfExport = DocumentPDFExportSession()
  @Environment(\.openURL) private var openURL

  private struct StatusAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    /// Where the message can be checked, such as a Notion page that was written.
    var linkURL: URL?
  }

  private func playbackAndShareActions(_ meeting: Meeting) -> some ToolbarContent {
    MeetingDetailToolbarActions(
      hasAudio: meeting.hasPlaybackAudio,
      isPlaying: player.isPlaying,
      isRecording: model.isRecording,
      play: { player.toggle() },
      share: {
        shareItems = [MeetingShareText.make(meeting: meeting, tasks: model.tasks)]
        isSharing = true
      }
    )
  }

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
              meetingHeader(meeting)

              if !meeting.recordingMarkers.isEmpty {
                RecordingMarkersView(markers: meeting.recordingMarkers,
                  onSeek: !meeting.hasPlaybackAudio && meeting.transcript.isEmpty ? nil : { time in
                    InteractionFeedback.shared.send(.tap)
                    model.detailPlaybackRequest = DetailPlaybackRequest(meetingID: meeting.id, time: time)
                  },
                  onDelete: { model.removeMeetingRecordingMarker(meetingID: meeting.id, markerID: $0) })
              }

              MemoraSectionPicker(
                items: MeetingDetailSection.allCases,
                selection: $selectedSection,
                title: \.label
              )

              sectionContent(meeting)
              if selectedSection == .summary, !meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MeetingQuestionSuggestionsView(meetingID: meeting.id)
              }
            }
            .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
            .padding(.horizontal, MemoraSpacing.screen)
            .frame(maxWidth: .infinity)
            // Room to scroll the last section clear of the floating AI composer.
            .padding(.bottom, model.bottomContentClearance)
          }
          .background(MemoraPalette.background)
          .onAppear {
            detailTab = model.selectedTab
            model.pushActiveDetail(meeting.id)
            // Ask AI stays on screen however far the record is scrolled.
            model.isDetailComposerVisible = true
            player.load(input: meeting.audioPlaybackInput, title: meeting.displayTitle)
            if !didApplyInitialPlayback, let start = initialPlaybackStart {
              didApplyInitialPlayback = true
              applyPlaybackRequest(start, meeting: meeting, proxy: proxy)
            }

          }
          .onChange(of: meeting.audioPlaybackInput) { _, input in
            player.load(input: input, title: meeting.displayTitle)
          }
          .onChange(of: player.errorMessage, initial: true) { _, message in
            if let message { statusAlert = StatusAlert(title: "音声を再生できません", message: message) }
          }
          .onChange(of: model.isRecording) { _, recording in
            // A recording owns the audio session, so playback steps aside.
            if recording { player.pause() }
          }
          .onDisappear {
            player.stop()
            // Only the detail that owns the transport gives it up, so a stacked
            // screen cannot silence the one below it.
            if model.activePlayback === player {
              model.activePlayback = nil
            }
          }
          .onChange(of: model.detailPlaybackRequest) { _, request in
            guard let request, request.meetingID == meeting.id else { return }
            applyPlaybackRequest(request.time, meeting: meeting, proxy: proxy, segmentID: request.segmentID)
            model.detailPlaybackRequest = nil
          }
          .onDisappear {
            model.popActiveDetail(meeting.id, tab: detailTab)
            model.isDetailComposerVisible = true
          }
          .scrollFocusedEditorAboveKeyboard(in: proxy)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("記録")
        .toolbar {
          if isSavingToNotion {
            ToolbarItem(placement: .topBarTrailing) {
              ProgressView()
                .accessibilityLabel("Notionへ保存中")
            }
          }
          playbackAndShareActions(meeting)
          ToolbarActionItem(usesSystemBackground: true) {
            Menu {
              Button("プライバシーと外部送信", icon: .lockShield) { isPrivacyPresented = true }
              Button("チームで共有", icon: .personBadgePlus) {
                Task { await model.shareMeetingWithTeam(meeting.id) }
              }
              Button("PDFで共有", icon: .docRichtext) {
                sharePDF(meeting)
              }
              Button("リンクをコピー", icon: .link) {
                copyLink(meeting)
              }
              Button(isSavingToNotion ? "Notionへ保存中…" : "Notionへ保存", icon: .arrowUpDoc) {
                saveToNotion(meeting)
              }
              .disabled(!NotionService.isConfigured || isSavingToNotion)
              Button(meeting.summary.isEmpty ? "要約する" : "要約し直す", icon: .sparkles) {
                isSummaryGenerationPresented = true
              }
              .disabled(meeting.transcript.isEmpty)
              .accessibilityIdentifier("meeting.summary.regenerate")
              if !meeting.summaryVersions.isEmpty {
                NavigationLink { SummaryHistoryView(meetingID: meeting.id) } label: {
                  Label("要約の履歴", icon: .clockArrowCirclepath)
                }
              }
              Button("要約をコピー", icon: .docOnDoc) { UIPasteboard.general.string = meeting.summary }
                .disabled(meeting.summary.isEmpty)
              Button("抽出情報を確認", icon: .listBulletRectangle) { isReviewingExtraction = true }
                .accessibilityIdentifier("meeting.summary.extraction")
              Button("タスクを追加", icon: .textBadgePlus) { isAddingTask = true }
              Button("要点・決定事項を編集", icon: .pencil) { isEditingHighlights = true }
              Button("参加者を編集", icon: .personBadgePlus) { isAddingPeople = true }
              if meeting.hasAudioFiles {
                Button("音声を削除（文字起こしと要約は残す）", icon: .waveformBadgeMinus) {
                  isRemovingAudio = true
                }
              }
              Button("プロジェクト", icon: .folder) {
                isChoosingSpace = true
              }
              Button("名前を変更", icon: .pencil) {
                isRenaming = true
              }
              Button("削除", icon: .trash, role: .destructive) {
                isDeleting = true
              }
            } label: {
              ToolbarActionLabel("その他", icon: .ellipsis)
            }
          }
        }
        .sheet(isPresented: $isRenaming) {
          RenameMeetingSheet(meeting: meeting)
        }
        .sheet(isPresented: $isSummaryGenerationPresented) {
          SummaryGenerationSheet(meetingID: meeting.id)
        }
        .sheet(isPresented: $isPrivacyPresented) {
          RecordPrivacySettingsView(meetingID: meeting.id)
        }
        .sheet(isPresented: $isAddingTask) { AddTaskView(meetingID: meeting.id) }
        .sheet(isPresented: $isReviewingExtraction) { SummaryExtractionView(meetingID: meeting.id) }
        .sheet(isPresented: $isEditingHighlights) { MeetingHighlightsEditor(meetingID: meeting.id) }
        .sheet(isPresented: $isAddingPeople) {
          AddPeopleSheet(meetingID: meeting.id)
        }
        .sheet(isPresented: $isChoosingSpace) {
          SpacePickerSheet(meetingID: meeting.id)
        }
        .sheet(isPresented: $isSharing) {
          ActivityView(items: shareItems, onComplete: cleanUpSharedFiles)
        }
        .alert(item: $statusAlert) { alert in
          if let url = alert.linkURL {
            return Alert(
              title: Text(alert.title),
              message: Text(alert.message),
              primaryButton: .default(Text("開いて確認")) { openURL(url) },
              secondaryButton: .cancel(Text("OK"))
            )
          }
          return Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            dismissButton: .default(Text("OK"))
          )
        }
        .confirmationDialog("音声を削除しますか？", isPresented: $isRemovingAudio, titleVisibility: .visible) {
          Button("音声を削除", role: .destructive) {
            model.removeMeetingAudio(meeting.id)
          }
          Button("キャンセル", role: .cancel) {}
        } message: {
          Text("文字起こし・要約・ノート・タスクは残ります。取り消せます。")
        }
        .confirmationDialog("この会議を削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
          Button("削除", role: .destructive) {
            model.deleteMeeting(meeting.id)
            dismiss()
          }
          Button("キャンセル", role: .cancel) {}
        } message: {
          Text("「最近削除した項目」に移動します。30日間は元に戻せます。")
        }
        .onChange(of: player.isPlaying) { _, playing in
          // The transport is handed to the floating controls once playback has
          // begun, and stays for the rest of the visit. Inside a sheet those
          // controls are hidden behind it, so the bar is drawn here instead.
          guard playing else { return }
          if showsLocalPlaybackBar {
            localPlaybackStarted = true
          } else {
            model.activePlayback = player
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if showsLocalPlaybackBar, meeting.hasPlaybackAudio, localPlaybackStarted, !model.isInlineEditing {
            MeetingPlaybackBar(player: player)
              .padding(.horizontal, MemoraSpacing.md)
              .padding(.bottom, MemoraSpacing.sm)
              .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
          }
        }
        .animation(reduceMotion ? nil : MemoraMotion.control, value: localPlaybackStarted)
      } else {
        ContentUnavailableView("会議が見つかりません", icon: .docQuestionmark)
      }
    }
    .disabled(pdfExport.isRunning)
    .accessibilityHidden(pdfExport.isRunning)
    .overlay {
      if let progress = pdfExport.progress {
        ZStack {
          Color.black.opacity(0.08).ignoresSafeArea().accessibilityHidden(true)
          DocumentPDFExportProgressView(progress: progress) { pdfExport.cancel() }
        }
      }
    }
    .onDisappear { pdfExport.cancel() }
  }

  private func participantsRow(_ meeting: Meeting) -> some View {
    let names = model.participants(in: meeting.id).map(\.name).joined(separator: "、")
    return Button { isAddingPeople = true } label: {
      HStack(alignment: .firstTextBaseline, spacing: MemoraSpacing.sm) {
        Text("参加者")
        Text(names)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(icon: .chevronRight, size: MemoraIconMetrics.accessory)
          .accessibilityHidden(true)
      }
      .font(MemoraTypography.secondary)
      .foregroundStyle(MemoraPalette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(minHeight: MemoraSpacing.touchTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("参加者、\(names)")
    .accessibilityHint("参加者を編集します")
  }

  private func copyLink(_ meeting: Meeting) {
    guard let url = MeetingLink.url(for: meeting.id) else { return }
    UIPasteboard.general.string = url.absoluteString
    statusAlert = StatusAlert(title: "この端末の記録へのリンク", message: "コピーしました。このリンクは、この端末のMemoraでのみ開けます。")
  }

  private func sharePDF(_ meeting: Meeting) {
    let workspaceID = model.currentTeamID
    let generation = model.aiWorkspaceGeneration
    let tasks = model.tasks.filter { $0.meetingID == meeting.id }
    pdfExport.start(isCurrent: {
      model.currentTeamID == workspaceID && model.aiWorkspaceGeneration == generation
        && !model.isRestoring && !model.isStoreProtected
        && model.meeting(id: meeting.id) == meeting
        && model.tasks.filter { $0.meetingID == meeting.id } == tasks
    }, operation: { progress in
      try await MeetingPDF.write(meeting: meeting, tasks: tasks, onProgress: progress)
    }, completed: { url in
      shareItems = [url]
      isSharing = true
    }, failed: { message in
      statusAlert = StatusAlert(title: "PDFを作成できませんでした", message: message)
    })
  }

  private func cleanUpSharedFiles() {
    ArtifactExportFile.removeTemporary(shareItems)
    shareItems = []
  }

  private func saveToNotion(_ meeting: Meeting) {
    guard !isSavingToNotion, let context = LocalImportContext(in: model) else { return }
    isSavingToNotion = true
    Task {
      defer { isSavingToNotion = false }
      do {
        let outcome = try await model.saveMeetingToNotion(meeting.id, environment: .live)
        guard context.isCurrent(in: model) else { return }
        statusAlert = StatusAlert(
          title: "Notion",
          message: "Notionに保存しました。",
          linkURL: outcome.pageURL
        )
      } catch let partial as NotionService.PartialPageFailure {
        guard context.isCurrent(in: model) else { return }
        statusAlert = StatusAlert(
          title: "Notion",
          message: partial.message,
          linkURL: partial.pageURL
        )
      } catch NotionService.Failure.unknownOutcome {
        guard context.isCurrent(in: model) else { return }
        // The page may or may not exist; sending again could make a duplicate.
        statusAlert = StatusAlert(
          title: "Notion",
          message: "保存できたか確認できませんでした。重複を避けるため自動では再送しません。Notionを開いて確認してください。"
        )
      } catch NotionService.Failure.authorizationChanged {
        guard context.isCurrent(in: model) else { return }
        statusAlert = StatusAlert(title: "Notion", message: RecordAccessPolicy.refusal)
      } catch {
        guard context.isCurrent(in: model) else { return }
        statusAlert = StatusAlert(
          title: "Notion",
          message: "Notionに保存できませんでした。設定のトークンと保存先を確認してください。"
        )
      }
    }
  }

  /// Brings the detail to its transcript at a time: plays from there when the
  /// record has audio, and otherwise just highlights the line so the source is
  /// still identifiable.
  private func applyPlaybackRequest(_ time: TimeInterval?, meeting: Meeting, proxy: ScrollViewProxy, segmentID: UUID? = nil) {
    selectedSection = meeting.transcript.isEmpty ? .summary : .transcript
    // An untimed reference can still focus its exact transcript segment.
    if let time, meeting.hasPlaybackAudio && !model.isRecording {
      player.seek(to: time)
      player.play()
    }
    guard let segment = segmentID.flatMap({ id in meeting.transcript.first { $0.id == id } })
      ?? time.flatMap({ time in meeting.transcript.last { $0.timestamp <= time } }) else { return }
    focusedSegmentID = segment.id
    Task { @MainActor in
      // Let the transcript render before scrolling to the line.
      try? await Task.sleep(for: .milliseconds(150))
      withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
        proxy.scrollTo(segment.id, anchor: .center)
      }
    }
  }

  @ViewBuilder
  private func sectionContent(_ meeting: Meeting) -> some View {
    switch selectedSection {
    case .summary:
      switch meeting.status {
      case .waitingForTranscription:
        ManualAIProcessingCard(symbol: .textBubble, title: "文字起こし前",
          detail: "", actionTitle: "文字起こしする") {
          model.startTranscription(meeting.id)
        }
      case .waitingForSummary:
        let pendingJob = model.pendingSummaryJobs.first { $0.meetingID == meeting.id }
        ManualAIProcessingCard(symbol: .sparkles,
          title: pendingJob == nil ? "要約前" : "要約が途中で止まりました",
          detail: "", actionTitle: pendingJob == nil ? "要約する" : "もう一度要約する") {
          isSummaryGenerationPresented = true
        }
      case .importing, .transcribing, .organizing:
        ProcessingOverview(meeting: meeting)
      case .failed(let message):
        FailureOverview(message: message, retry: {
          retryFailedStep(meeting)
        }, showsSummaryDiagnostics: !meeting.transcript.isEmpty)
      case .partialFailure(let message):
        PartialFailureBanner(message: message) {
          retryFailedStep(meeting)
        }
        insightContent(meeting)
      case .ready:
        insightContent(meeting)
      }
    case .transcript:
      MeetingTranscriptContent(
        meeting: meeting,
        player: player,
        focusedSegmentID: focusedSegmentID
      )
    case .notes:
      MeetingNotesContent(meetingID: meeting.id)
    }
  }

  /// A record that already has its transcript failed at the summary, so the
  /// retry reopens the summary choice rather than transcribing again.
  private func retryFailedStep(_ meeting: Meeting) {
    if meeting.transcript.isEmpty {
      model.retryProcessing(meeting.id)
    } else {
      isSummaryGenerationPresented = true
    }
  }

  private func meetingHeader(_ meeting: Meeting) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(meeting.displayTitle)
        .font(MemoraTypography.screenTitle)
        .memoraTextReveal()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      Text([MemoraFormat.meetingDate(meeting.createdAt), meeting.duration == 0
        ? String(localized: "時間不明", comment: "Audio duration could not be read")
        : MemoraFormat.duration(meeting.duration), meeting.source.label].joined(separator: " · "))
        .font(MemoraTypography.secondary)
        .foregroundStyle(MemoraPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      if SampleContent.isSample(meetingID: meeting.id) {
        if !meeting.displayTitle.contains("（サンプル）") { SampleTag() }
      }

      if !model.participants(in: meeting.id).isEmpty { participantsRow(meeting) }

      if !meeting.hasAudioFiles, !SampleContent.isSample(meetingID: meeting.id) {
        Label("音声なし", icon: .waveformSlash)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.top, MemoraSpacing.sm)
  }

  @ViewBuilder
  private func insightContent(_ meeting: Meeting) -> some View {
    // Offered only when the records give a reason; otherwise nothing shows.
    let suggestions = model.projectSuggestions(for: meeting)
    let hasTasks = !model.tasks(forMeeting: meeting.id).isEmpty
    if !suggestions.isEmpty {
      ProjectSuggestionCard(meeting: meeting, suggestions: suggestions)
        .transition(.opacity)
    }

    if FeatureFlags.isInlineSummaryPosterEnabled,
       !meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      MeetingSummaryPosterEntry(meetingID: meeting.id)
    }

    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      // A generated document reads and edits at body size; a short summary
      // keeps its large single-text look.
      let isDocument = MarkdownBlockParser.hasBlockStructure(meeting.summary)
      InlineMarkdownEditor(
        text: meeting.summary,
        placeholder: "要約を追加",
        font: MemoraTypography.readingBody,
        minHeight: isDocument ? 320 : 120,
        rendersBlocks: true,
        draftKey: "meeting.\(meeting.id).summary",
        animatesReading: true,
        hidesDocumentTitle: true,
        onCommit: { await model.updateMeetingSummary(meeting.id, summary: $0) }
      )
    }

    if hasTasks {
      CollapsibleInsightSection(.tasks) {
        MeetingTasksSection(meetingID: meeting.id)
      }
    }

  }

}
