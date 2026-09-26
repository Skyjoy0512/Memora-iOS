import PhotosUI
import SwiftUI
import UIKit

struct MeetingDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var meetingID: UUID
  /// When set, the transcript opens and plays from here — used when an AI answer's
  /// source line is tapped.
  var initialPlaybackStart: TimeInterval?
  /// True when this detail is opened inside a sheet (from an AI answer), where
  /// the root transport is hidden behind it. The bar is then shown at this
  /// screen's own bottom, where nothing else floats.
  var showsLocalPlaybackBar = false
  @State private var selectedSection = MeetingDetailSection.summary
  @State private var isRenaming = false
  @State private var isDeleting = false
  @State private var isRemovingAudio = false
  @State private var isSummaryGenerationPresented = false
  @State private var isAddingPeople = false
  @State private var isChoosingSpace = false
  @State private var isSharing = false
  @State private var shareItems: [Any] = []
  /// The play button appears after the screen settles, so it reads as splitting
  /// off the trailing controls rather than popping in.
  @State private var isPlayButtonRevealed = false
  @State private var statusAlert: StatusAlert?
  @State private var player = AudioPlayerService()
  /// The line the initial time points at, highlighted even without audio.
  @State private var focusedSegmentID: UUID?
  /// Set when this sheet-opened detail has begun playing, so its local bar stays.
  @State private var localPlaybackStarted = false
  /// The initial time is applied once; a later `onAppear` must not seek again.
  @State private var didApplyInitialPlayback = false

  @State private var isSavingToNotion = false
  /// The PDF export in progress, with its progress, while it runs.
  @State private var pdfExportProgress: Double?
  @State private var pdfExportTask: Task<Void, Never>?
  @Environment(\.openURL) private var openURL

  private struct StatusAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    /// Where the message can be checked, such as a Notion page that was written.
    var linkURL: URL?
  }

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 22) {
              meetingHeader(meeting)

              participantsRow(meeting)

              Picker("会議の表示", selection: $selectedSection) {
                ForEach(MeetingDetailSection.allCases) { section in
                  Text(section.label).tag(section)
                }
              }
              .pickerStyle(.segmented)

              sectionContent(meeting)
                .id(selectedSection)
                .transition(sectionTransition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            // Room to scroll the last section clear of the floating AI composer.
            .padding(.bottom, model.bottomContentClearance)
            .animation(reduceMotion ? nil : MemoraMotion.control, value: selectedSection)
            .animation(reduceMotion ? nil : MemoraMotion.screen, value: meeting.status)
          }
          .background(Color(uiColor: .systemBackground))
          .overlay {
            if let progress = pdfExportProgress {
              pdfExportCard(progress)
            }
          }
          .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
          } action: { _, newOffset in
            updateScrollState(to: newOffset)
          }
          .onAppear {
            model.pushActiveDetail(meeting.id)
            model.isDetailComposerVisible = true
            player.load(meeting.audioURL, title: meeting.displayTitle)
            if !didApplyInitialPlayback, let start = initialPlaybackStart {
              didApplyInitialPlayback = true
              applyPlaybackRequest(start, meeting: meeting, proxy: proxy)
            }
            withAnimation(
              reduceMotion
                ? nil
                : .spring(response: 0.45, dampingFraction: 0.72).delay(0.08)
            ) {
              isPlayButtonRevealed = true
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
            model.popActiveDetail(meeting.id)
            model.isDetailComposerVisible = true
          }
          .scrollFocusedEditorAboveKeyboard(in: proxy)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("前に戻る", systemImage: "chevron.left") {
              dismiss()
            }
            .labelStyle(.iconOnly)
          }
          ToolbarItem(placement: .principal) {
            if meeting.audioURL != nil, isPlayButtonRevealed {
              Button {
                player.toggle()
              } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                  .font(.headline.weight(.bold))
                  .frame(width: 40, height: 40)
                  .contentShape(Circle())
              }
              .buttonStyle(.plain)
              .memoraGlass(in: Circle(), interactive: true)
              .disabled(model.isRecording)
              .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")
              // Grows out of the trailing controls the way a Liquid Glass
              // selection splits off its neighbour.
              .transition(
                .asymmetric(
                  insertion: .scale(scale: 0.2, anchor: .trailing)
                    .combined(with: .opacity)
                    .combined(with: .offset(x: 120)),
                  removal: .opacity
                )
              )
            }
          }
          if isSavingToNotion {
            ToolbarItem(placement: .topBarTrailing) {
              ProgressView()
                .accessibilityLabel("Notionへ保存中")
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: MeetingShareText.make(meeting: meeting, tasks: model.tasks)) {
              Label("共有", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Menu("その他", systemImage: "ellipsis") {
              Button("チームで共有", systemImage: "person.badge.plus") {
                Task { await model.shareMeetingWithTeam(meeting.id) }
              }
              Button("PDFで共有", systemImage: "doc.richtext") {
                sharePDF(meeting)
              }
              Button("リンクをコピー", systemImage: "link") {
                copyLink(meeting)
              }
              Button(isSavingToNotion ? "Notionへ保存中…" : "Notionへ保存", systemImage: "arrow.up.doc") {
                saveToNotion(meeting)
              }
              .disabled(!NotionService.isConfigured || isSavingToNotion)
              Button("要約をやり直す", systemImage: "sparkles") {
                isSummaryGenerationPresented = true
              }
              .disabled(meeting.transcript.isEmpty)
              if meeting.audioURL != nil {
                Button("音声を削除（文字起こしと要約は残す）", systemImage: "waveform.badge.minus") {
                  isRemovingAudio = true
                }
              }
              Button("プロジェクト", systemImage: "folder") {
                isChoosingSpace = true
              }
              Button("名前を変更", systemImage: "pencil") {
                isRenaming = true
              }
              Button("削除", systemImage: "trash", role: .destructive) {
                isDeleting = true
              }
            }
          }
        }
        .sheet(isPresented: $isRenaming) {
          RenameMeetingSheet(meeting: meeting)
        }
        .sheet(isPresented: $isSummaryGenerationPresented) {
          SummaryGenerationSheet(meetingID: meeting.id)
        }
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
        .sensoryFeedback(.selection, trigger: selectedSection)
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
              .padding(.horizontal, 12)
              .padding(.bottom, 8)
              .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
          }
        }
        .animation(reduceMotion ? nil : MemoraMotion.control, value: localPlaybackStarted)
      } else {
        ContentUnavailableView("会議が見つかりません", systemImage: "doc.questionmark")
      }
    }
  }

  /// People tagged on the recording, shown as round story-style avatars with a
  /// round add button at the end.
  private func participantsRow(_ meeting: Meeting) -> some View {
    let participants = model.participants(in: meeting.id)

    return ScrollView(.horizontal) {
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
              Image(systemName: participants.isEmpty ? "person.badge.plus" : "plus")
                .font(.title3)
                .foregroundStyle(.secondary)
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
      .padding(.horizontal, 18)
      .padding(.vertical, 2)
    }
    .scrollIndicators(.hidden)
    .padding(.horizontal, -18)
  }

  private func copyLink(_ meeting: Meeting) {
    guard let url = MeetingLink.url(for: meeting.id) else { return }
    UIPasteboard.general.string = url.absoluteString
    statusAlert = StatusAlert(title: "この端末の記録へのリンク", message: "コピーしました。このリンクは、この端末のMemoraでのみ開けます。")
  }

  private func sharePDF(_ meeting: Meeting) {
    guard pdfExportTask == nil else { return }
    pdfExportProgress = 0
    pdfExportTask = Task {
      defer {
        pdfExportProgress = nil
        pdfExportTask = nil
      }
      do {
        let url = try await MeetingPDF.write(meeting: meeting, tasks: model.tasks) { progress in
          pdfExportProgress = progress
        }
        shareItems = [url]
        isSharing = true
      } catch MeetingPDF.ExportError.cancelled {
        // Cancelled on purpose; nothing to report.
        return
      } catch {
        statusAlert = StatusAlert(
          title: "PDFを作成できませんでした",
          message: "記録は残っています。もう一度お試しください。"
        )
      }
    }
  }

  /// Shows that the export is running and how far along it is, with a way out of
  /// a long one.
  private func pdfExportCard(_ progress: Double) -> some View {
    VStack(spacing: 12) {
      ProgressView(value: progress)
        .progressViewStyle(.linear)
        .tint(.primary)

      HStack(spacing: 12) {
        Text("PDFを作成しています… \(Int(progress * 100))%")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Button("キャンセル") { cancelPDFExport() }
          .font(.subheadline.weight(.semibold))
      }
    }
    .padding(16)
    .frame(maxWidth: 320)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    .padding()
    .accessibilityElement(children: .combine)
    .accessibilityLabel("PDFを作成しています。\(Int(progress * 100))パーセント")
    .accessibilityAction(named: "キャンセル") { cancelPDFExport() }
  }

  private func cancelPDFExport() {
    pdfExportTask?.cancel()
  }

  private func cleanUpSharedFiles() {
    MeetingPDF.discard(shareItems)
    shareItems = []
  }

  private func saveToNotion(_ meeting: Meeting) {
    guard !isSavingToNotion else { return }
    isSavingToNotion = true
    Task {
      defer { isSavingToNotion = false }
      do {
        let outcome = try await NotionService.save(meeting: meeting, tasks: model.tasks)
        statusAlert = StatusAlert(
          title: "Notion",
          message: "Notionに保存しました。",
          linkURL: outcome.pageURL
        )
      } catch let partial as NotionService.PartialPageFailure {
        statusAlert = StatusAlert(
          title: "Notion",
          message: partial.message,
          linkURL: partial.pageURL
        )
      } catch NotionService.Failure.unknownOutcome {
        // The page may or may not exist; sending again could make a duplicate.
        statusAlert = StatusAlert(
          title: "Notion",
          message: "保存できたか確認できませんでした。重複を避けるため自動では再送しません。Notionを開いて確認してください。"
        )
      } catch {
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
    selectedSection = .transcript
    // A request with no time only opens the transcript; it does not play.
    guard let time else { return }
    if meeting.audioURL != nil {
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

  private var sectionTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
  }

  private func updateScrollState(to newOffset: CGFloat) {
    let shouldShowComposer = newOffset < 64

    if model.isDetailComposerVisible != shouldShowComposer {
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        model.isDetailComposerVisible = shouldShowComposer
      }
    }
  }

  @ViewBuilder
  private func sectionContent(_ meeting: Meeting) -> some View {
    switch selectedSection {
    case .summary:
      switch meeting.status {
      case .waitingForTranscription:
        ManualAIProcessingCard(
          symbol: "waveform.badge.plus",
          title: "文字起こしはまだ始まっていません",
          detail: meeting.source == .recording
            ? "復旧した音声は端末に保存済みです。開始すると文字起こしを行います。録音は自動で再開しません。"
            : "音声は端末に保存済みです。必要な時に開始してください。",
          actionTitle: "文字起こしを開始"
        ) {
          model.startTranscription(meeting.id)
        }
      case .waitingForSummary:
        ManualAIProcessingCard(
          symbol: "sparkles",
          title: "文字起こしが完成しました",
          detail: "要約方法を選ぶまで、追加のAI処理は行いません。",
          actionTitle: "要約を生成"
        ) {
          isSummaryGenerationPresented = true
        }
      case .importing, .transcribing, .organizing:
        ProcessingOverview(meeting: meeting)
      case .failed(let message):
        FailureOverview(message: message) {
          model.retryProcessing(meeting.id)
        }
      case .partialFailure(let message):
        PartialFailureBanner(message: message) {
          model.retryProcessing(meeting.id)
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

  private func meetingHeader(_ meeting: Meeting) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(meeting.title)
        .font(.largeTitle.bold())
        .tracking(-0.6)
        .memoraTextReveal()

      HStack(spacing: 8) {
        Text(MemoraFormat.meetingDate(meeting.createdAt))
        Text("·")
        Text(MemoraFormat.duration(meeting.duration))
        Text("·")
        Text(meeting.source.label)
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)

      if meeting.audioURL == nil, !SampleContent.isSample(meetingID: meeting.id) {
        Label("音声は削除済み", systemImage: "waveform.slash")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.top, 8)
  }

  @ViewBuilder
  private func insightContent(_ meeting: Meeting) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("サマリー", systemImage: "text.alignleft")
        .font(.title3.bold())
        .foregroundStyle(.primary)
        .memoraTextReveal()

      InlineMarkdownEditor(
        text: meeting.summary,
        placeholder: "要約を追加",
        font: .title3.weight(.medium),
        minHeight: 120,
        draftKey: "meeting.\(meeting.id).summary",
        onCommit: { await model.updateMeetingSummary(meeting.id, summary: $0) }
      )
      .memoraTextReveal(delay: 0.04)
    }
    .insightCard()
    .memoraAppear()

    InlineEditableList(
      title: "決まったこと",
      symbol: "checkmark.seal",
      items: meeting.decisions,
      emptyText: "明確な決定は見つかりませんでした",
      onCommit: { model.updateMeetingList(meeting.id, \.decisions, items: $0) }
    )
    .insightCard()
    .memoraAppear(delay: 0.05)

    MeetingTasksSection(meetingID: meeting.id)
      .insightCard()
      .memoraAppear(delay: 0.1)

    InlineEditableList(
      title: "まだ決まっていないこと",
      symbol: "questionmark.bubble",
      items: meeting.openQuestions,
      emptyText: "未決事項はありません",
      onCommit: { model.updateMeetingList(meeting.id, \.openQuestions, items: $0) }
    )
    .insightCard()
    .memoraAppear(delay: 0.15)

    InlineEditableList(
      title: "重要なポイント",
      symbol: "pin",
      items: meeting.keyPoints,
      emptyText: "ポイントを抽出中です",
      onCommit: { model.updateMeetingList(meeting.id, \.keyPoints, items: $0) }
    )
    .insightCard()
    .memoraAppear(delay: 0.2)
  }

}

extension View {
  /// Groups one summary section — heading and content — into a single block so
  /// the sections do not blur into one another.
  func insightCard() -> some View {
    padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .memoraCard(radius: 20)
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
      "サマリー"
    case .transcript:
      "文字起こし"
    case .notes:
      "ノート"
    }
  }

}


