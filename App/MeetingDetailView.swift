import PhotosUI
import SwiftUI
import UIKit

struct MeetingDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var meetingID: UUID
  @State private var selectedSection = MeetingDetailSection.summary
  @State private var isRenaming = false
  @State private var isDeleting = false
  @State private var isCompactTitleVisible = false
  @State private var isSummaryGenerationPresented = false
  @State private var isAddingPeople = false
  @State private var isChoosingSpace = false
  @State private var isSharing = false
  @State private var shareItems: [Any] = []
  @State private var statusAlert: StatusAlert?
  @State private var player = AudioPlayerService()
  @State private var scrubTime: Double?

  private struct StatusAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
  }

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 22) {
              meetingHeader(meeting)

              participantsRow(meeting)

              if meeting.audioURL != nil {
                playerCard(meeting)
              }

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
          .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
          } action: { _, newOffset in
            updateScrollState(to: newOffset)
          }
          .onAppear {
            model.activeDetailMeetingID = meeting.id
            model.isDetailComposerVisible = true
            player.load(meeting.audioURL)
          }
          .onChange(of: model.isRecording) { _, recording in
            // A recording owns the audio session, so playback steps aside.
            if recording { player.pause() }
          }
          .onDisappear {
            player.stop()
          }
          .onDisappear {
            if model.activeDetailMeetingID == meeting.id {
              model.activeDetailMeetingID = nil
            }
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
            Text(meeting.title)
              .font(.headline)
              .lineLimit(1)
              .opacity(isCompactTitleVisible ? 1 : 0)
              .accessibilityHidden(!isCompactTitleVisible)
              .animation(reduceMotion ? nil : MemoraMotion.control, value: isCompactTitleVisible)
          }
          ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: MeetingShareText.make(meeting: meeting, tasks: model.tasks)) {
              Label("共有", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Menu("その他", systemImage: "ellipsis") {
              Button("PDFで共有", systemImage: "doc.richtext") {
                sharePDF(meeting)
              }
              Button("リンクをコピー", systemImage: "link") {
                copyLink(meeting)
              }
              Button("Notionへ保存", systemImage: "arrow.up.doc") {
                saveToNotion(meeting)
              }
              .disabled(!NotionService.isConfigured)
              Button("要約をやり直す", systemImage: "sparkles") {
                isSummaryGenerationPresented = true
              }
              .disabled(meeting.transcript.isEmpty)
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
          ActivityView(items: shareItems)
        }
        .alert(item: $statusAlert) { alert in
          Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            dismissButton: .default(Text("OK"))
          )
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
      } else {
        ContentUnavailableView("会議が見つかりません", systemImage: "doc.questionmark")
      }
    }
  }

  /// Plays the recording: play/pause, position, 15-second jumps, and speed.
  private func playerCard(_ meeting: Meeting) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 14) {
        Button {
          player.toggle()
        } label: {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(width: 48, height: 48)
            .background(Circle().fill(.primary))
        }
        .buttonStyle(.plain)
        .disabled(model.isRecording)
        .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")

        VStack(alignment: .leading, spacing: 2) {
          Text(MemoraFormat.duration(scrubTime ?? player.currentTime))
            .font(.subheadline.monospacedDigit().weight(.medium))
          Text(MemoraFormat.duration(player.duration))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)

        Button("15秒戻す", systemImage: "gobackward.15") {
          player.skip(by: -15)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .disabled(player.duration == 0)

        Button("15秒進める", systemImage: "goforward.15") {
          player.skip(by: 15)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .disabled(player.duration == 0)

        speedMenu
      }

      Slider(value: seekBinding, in: 0...max(player.duration, 0.1)) { editing in
        if !editing, let time = scrubTime {
          player.seek(to: time)
          scrubTime = nil
        }
      }
      .disabled(player.duration == 0)
      .accessibilityLabel("再生位置")

      if let message = player.errorMessage {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if model.isRecording {
        Label("録音中は再生できません", systemImage: "mic")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(16)
    .memoraCard()
    .memoraAppear()
  }

  private var speedMenu: some View {
    Menu {
      ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { option in
        Button {
          player.rate = Float(option)
        } label: {
          if player.rate == Float(option) {
            Label(speedLabel(option), systemImage: "checkmark")
          } else {
            Text(speedLabel(option))
          }
        }
      }
    } label: {
      Text(speedLabel(Double(player.rate)))
        .font(.subheadline.weight(.medium))
        .frame(minWidth: 44, minHeight: 32)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("再生速度")
  }

  private func speedLabel(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))x" : String(format: "%.1fx", value)
  }

  private var seekBinding: Binding<Double> {
    Binding {
      scrubTime ?? player.currentTime
    } set: { newValue in
      scrubTime = newValue
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
    guard let url = MeetingPDF.write(meeting: meeting, tasks: model.tasks) else { return }
    shareItems = [url]
    isSharing = true
  }

  private func saveToNotion(_ meeting: Meeting) {
    Task {
      do {
        try await NotionService.save(meeting: meeting, tasks: model.tasks)
        statusAlert = StatusAlert(title: "Notion", message: "Notionに保存しました。")
      } catch {
        statusAlert = StatusAlert(title: "Notion", message: "Notionに保存できませんでした。設定のトークンと保存先を確認してください。")
      }
    }
  }

  private var sectionTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
  }

  private func updateScrollState(to newOffset: CGFloat) {
    let compactTitleShouldShow = newOffset > 76
    if compactTitleShouldShow != isCompactTitleVisible {
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        isCompactTitleVisible = compactTitleShouldShow
      }
    }

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
          detail: "音声は端末に保存済みです。必要な時に開始してください。",
          actionTitle: "文字起こしを開始"
        ) {
          model.startImportedTranscription(meeting.id)
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
      MeetingTranscriptContent(meeting: meeting, player: player)
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
        onCommit: { model.updateMeetingSummary(meeting.id, summary: $0) }
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


