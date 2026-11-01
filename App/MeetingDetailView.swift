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
      hasAudio: meeting.audioURL != nil,
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

              if !model.participants(in: meeting.id).isEmpty { participantsRow(meeting) }

              if !meeting.recordingMarkers.isEmpty {
                RecordingMarkersView(markers: meeting.recordingMarkers,
                  onSeek: meeting.audioURL == nil && meeting.transcript.isEmpty ? nil : { time in
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
            player.load(meeting.audioURL, title: meeting.displayTitle)
            if !didApplyInitialPlayback, let start = initialPlaybackStart {
              didApplyInitialPlayback = true
              applyPlaybackRequest(start, meeting: meeting, proxy: proxy)
            }

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
            applyPlaybackRequest(request.time, meeting: meeting, proxy: proxy)
            model.detailPlaybackRequest = nil
          }
          .onDisappear {
            model.popActiveDetail(meeting.id, tab: detailTab)
            model.isDetailComposerVisible = true
          }
          .scrollFocusedEditorAboveKeyboard(in: proxy)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(meeting.displayTitle)
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
              Button("タスクを追加", icon: .textBadgePlus) { isAddingTask = true }
              Button("要点・決定事項を編集", icon: .pencil) { isEditingHighlights = true }
              Button("参加者を編集", icon: .personBadgePlus) { isAddingPeople = true }
              if meeting.audioURL != nil {
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
          if showsLocalPlaybackBar, meeting.audioURL != nil, localPlaybackStarted, !model.isInlineEditing {
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

  /// People tagged on the recording, shown as round story-style avatars with a
  /// round add button at the end.
  @ViewBuilder
  private func participantsRow(_ meeting: Meeting) -> some View {
    let participants = model.participants(in: meeting.id)

    if participants.isEmpty {
      Button("参加者を追加", icon: .personBadgePlus) {
        isAddingPeople = true
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .frame(minHeight: 44)
    } else {
      ScrollView(.horizontal) {
        HStack(spacing: 14) {
          ForEach(participants) { person in
            PersonBubble(title: person.name, photoData: person.photoData, size: 56)
          }

          Button {
            isAddingPeople = true
          } label: {
            VStack(spacing: 6) {
              ZStack {
                Circle()
                  .fill(Color.primary.opacity(0.08))
                Image(icon: .plus, size: 20)
                  .foregroundStyle(.primary)
              }
              .frame(width: 56, height: 56)

              Text("追加")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("参加者を追加")
        }
        .padding(.horizontal, MemoraSpacing.lg)
        .padding(.vertical, MemoraSpacing.xxs)
      }
      .scrollIndicators(.hidden)
      .padding(.horizontal, -18)
    }
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
  private func applyPlaybackRequest(_ time: TimeInterval?, meeting: Meeting, proxy: ScrollViewProxy) {
    selectedSection = meeting.transcript.isEmpty ? .summary : .transcript
    // A request with no time only opens the transcript; it does not play.
    guard let time else { return }
    if meeting.audioURL != nil && !model.isRecording {
      player.seek(to: time)
      player.play()
    }
    guard let segment = meeting.transcript.last(where: { $0.timestamp <= time }) else { return }
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
        ManualAIProcessingCard(symbol: .textBubble, title: "音声を文字にする",
          detail: "", actionTitle: "文字起こしする") {
          model.startTranscription(meeting.id)
        }
      case .waitingForSummary:
        let pendingJob = model.pendingSummaryJobs.first { $0.meetingID == meeting.id }
        ManualAIProcessingCard(symbol: .sparkles,
          title: pendingJob == nil ? "文字起こしを要約する" : "要約が途中で止まりました",
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
        SampleTag()
        Text("表示用の架空データです。実際の音声・AI処理の結果ではありません。")
          .font(.caption).foregroundStyle(.secondary)
      }

      if meeting.audioURL == nil, !SampleContent.isSample(meetingID: meeting.id) {
        Label("音声なし", icon: .waveformSlash)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.top, MemoraSpacing.sm)
  }

  @ViewBuilder
  private func summaryActions(_ meeting: Meeting) -> some View {
    if !meeting.summaryVersions.isEmpty {
      NavigationLink { SummaryHistoryView(meetingID: meeting.id) } label: {
        Label("履歴", icon: .clockArrowCirclepath).font(.subheadline)
      }
      .frame(minHeight: 44)
      .accessibilityValue("\(meeting.summaryVersions.count)件")
    }
    Button("要約し直す", icon: .sparkles) { isSummaryGenerationPresented = true }
      .font(.subheadline)
      .frame(minHeight: 44)
      .accessibilityIdentifier("meeting.summary.regenerate")
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
      ViewThatFits(in: .horizontal) {
        HStack(spacing: MemoraSpacing.lg) { summaryActions(meeting) }
        VStack(alignment: .leading, spacing: MemoraSpacing.sm) { summaryActions(meeting) }
      }
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
        onCommit: { await model.updateMeetingSummary(meeting.id, summary: $0) }
      )
    }

    if !meeting.decisions.isEmpty {
      CollapsibleInsightSection(.decisions) {
        InlineEditableList(
          items: meeting.decisions,
          emptyText: "明確な決定は見つかりませんでした",
          onCommit: { model.updateMeetingList(meeting.id, \.decisions, items: $0) }
        )
      }
    }

    if hasTasks {
      CollapsibleInsightSection(.tasks) {
        MeetingTasksSection(meetingID: meeting.id)
      }
    }

    if !meeting.openQuestions.isEmpty {
      CollapsibleInsightSection(.openQuestions) {
        InlineEditableList(
          items: meeting.openQuestions,
          emptyText: "未決事項はありません",
          onCommit: { model.updateMeetingList(meeting.id, \.openQuestions, items: $0) }
        )
      }
    }

    if !meeting.keyPoints.isEmpty {
      CollapsibleInsightSection(.keyPoints) {
        InlineEditableList(
          items: meeting.keyPoints,
          emptyText: "重要なポイントはありません",
          onCommit: { model.updateMeetingList(meeting.id, \.keyPoints, items: $0) }
        )
      }
    }
  }

}

private enum MeetingDetailSection: String, CaseIterable, Identifiable {
  case summary
  case transcript
  case notes

  var id: Self { self }

  var label: String {
    switch self {
    case .summary:
      "要約"
    case .transcript:
      "文字起こし"
    case .notes:
      "ノート"
    }
  }

}
