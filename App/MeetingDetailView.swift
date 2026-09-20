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
  @State private var isSharing = false
  @State private var shareItems: [Any] = []
  @State private var statusAlert: StatusAlert?

  private struct StatusAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
  }

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
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
          .padding(.bottom, 120)
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
        }
        .onDisappear {
          if model.activeDetailMeetingID == meeting.id {
            model.activeDetailMeetingID = nil
          }
          model.isDetailComposerVisible = true
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
          Text("音声、文字起こし、議事録、関連タスクが削除されます。")
        }
        .sensoryFeedback(.selection, trigger: selectedSection)
      } else {
        ContentUnavailableView("会議が見つかりません", systemImage: "doc.questionmark")
      }
    }
  }

  /// People tagged on the recording, with a way to add more.
  private func participantsRow(_ meeting: Meeting) -> some View {
    let participants = model.participants(in: meeting.id)

    return ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(participants) { person in
          HStack(spacing: 6) {
            PersonAvatar(name: person.name, size: 22)
            Text(person.name)
              .font(.subheadline)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(Color.primary.opacity(0.06), in: Capsule())
        }

        Button {
          isAddingPeople = true
        } label: {
          Label(participants.isEmpty ? "参加者を追加" : "追加", systemImage: "person.badge.plus")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)

        Spacer(minLength: 0)
      }
    }
    .scrollIndicators(.hidden)
  }

  private func copyLink(_ meeting: Meeting) {
    guard let url = MeetingLink.url(for: meeting.id) else { return }
    UIPasteboard.general.string = url.absoluteString
    statusAlert = StatusAlert(title: "共有リンク", message: "共有リンクをコピーしました。Memoraを入れている人は開けます。")
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
      MeetingTranscriptContent(meeting: meeting)
    case .notes:
      MeetingNotesContent(noteText: Binding(
        get: { model.meeting(id: meeting.id)?.notes ?? "" },
        set: { model.updateMeetingNotes(meeting.id, notes: $0) }
      ))
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

      HStack(spacing: 6) {
        Image(systemName: "lock.fill")
        Text("端末に保存")
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
    }
    .padding(.top, 8)
  }

  @ViewBuilder
  private func insightContent(_ meeting: Meeting) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(meeting.summary)
        .font(.title3.weight(.medium))
        .lineSpacing(6)
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
        .memoraTextReveal(delay: 0.04)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.vertical, 28)
    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .memoraAppear()

    InsightSection(
      title: "決まったこと",
      symbol: "checkmark.seal",
      color: .primary,
      items: meeting.decisions,
      emptyText: "明確な決定は見つかりませんでした"
    )
    .memoraAppear(delay: 0.05)

    MeetingTasksSection(meetingID: meeting.id)
      .memoraAppear(delay: 0.1)

    InsightSection(
      title: "まだ決まっていないこと",
      symbol: "questionmark.bubble",
      color: .primary,
      items: meeting.openQuestions,
      emptyText: "未決事項はありません"
    )
    .memoraAppear(delay: 0.15)

    InsightSection(
      title: "重要なポイント",
      symbol: "pin",
      color: .primary,
      items: meeting.keyPoints,
      emptyText: "ポイントを抽出中です"
    )
    .memoraAppear(delay: 0.2)
  }

}

private struct ManualAIProcessingCard: View {
  var symbol: String
  var title: String
  var detail: String
  var actionTitle: String
  var action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        MemoraIconBadge(symbol: symbol, size: 42)
        VStack(alignment: .leading, spacing: 5) {
          Text(title)
            .font(.headline)
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Label("実行するまでAI利用は発生しません", systemImage: "hand.raised")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)

      Button(actionTitle, systemImage: symbol, action: action)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .memoraAppear()
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

private struct MeetingTranscriptContent: View {
  var meeting: Meeting

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("文字起こし")
          .font(.title2.bold())
          .memoraTextReveal()
        Spacer()
        NavigationLink("編集", value: LibraryRoute.transcript(meeting.id))
          .font(.subheadline)
          .disabled(meeting.transcript.isEmpty)
      }

      if meeting.transcript.isEmpty {
        ContentUnavailableView {
          Label("文字起こし中", systemImage: "text.bubble")
        } description: {
          Text("完成した発言から、この画面に表示されます。")
        }
        .frame(maxWidth: .infinity)
      } else {
        ForEach(meeting.transcript) { segment in
          HStack(alignment: .top, spacing: 12) {
            Text(MemoraFormat.duration(segment.timestamp))
              .font(.caption.monospacedDigit().weight(.medium))
              .foregroundStyle(.secondary)
              .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 4) {
                Text(segment.speaker)
                  .font(.caption.weight(.semibold))
                if !segment.speakerIsCertain {
                  Image(systemName: "questionmark")
                    .font(.caption2.bold())
                }
              }
              .foregroundStyle(segment.speakerIsCertain ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

              Text(segment.text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
            }
          }
        }
      }
    }
    .memoraAppear()
  }
}

private struct MeetingNotesContent: View {
  @Binding var noteText: String
  @State private var photoItem: PhotosPickerItem?
  @State private var photoData: Data?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("ノート")
          .font(.title2.bold())
          .memoraTextReveal()

        Spacer()

        PhotosPicker(selection: $photoItem, matching: .images) {
          Label("写真を追加", systemImage: "photo.badge.plus")
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
      }

      if let photoData, let image = UIImage(data: photoData) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .frame(height: 220)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
      }

      TextEditor(text: $noteText)
        .font(.body)
        .frame(minHeight: 360)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
          if noteText.isEmpty {
            Text("タップして入力")
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 5)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
          }
        }
    }
    .memoraAppear()
    .animation(.smooth, value: photoData)
    .onChange(of: photoItem) { _, newValue in
      Task {
        photoData = try? await newValue?.loadTransferable(type: Data.self)
      }
    }
  }
}

private struct InsightSection: View {
  var title: String
  var symbol: String
  var color: Color
  var items: [String]
  var emptyText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: symbol)
        .font(.title3.bold())
        .foregroundStyle(color)
        .memoraTextReveal()

      if items.isEmpty {
        Text(emptyText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(items, id: \.self) { item in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
              .fill(color)
              .frame(width: 5, height: 5)
            Text(item)
              .font(.body)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }
}

private struct MeetingTasksSection: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID

  var body: some View {
    let meetingTasks = model.tasks.filter { $0.meetingID == meetingID }
    VStack(alignment: .leading, spacing: 12) {
      Label("次にすること", systemImage: "arrow.right.circle")
        .font(.title3.bold())
        .foregroundStyle(.primary)

      if meetingTasks.isEmpty {
        Text("この会議からタスクは見つかりませんでした")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(meetingTasks) { task in
          TaskRow(task: task)
        }
      }
    }
  }
}

private struct ProcessingOverview: View {
  var meeting: Meeting

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        ProgressView()
          .controlSize(.large)
        VStack(alignment: .leading, spacing: 3) {
          Text(primaryText)
            .font(.headline)
          Text("終わった内容から順に使えるようになります")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        ProcessStep(title: "音声を保存", isComplete: true, isCurrent: false)
        ProcessStep(title: "文字にする", isComplete: hasTranscript, isCurrent: !hasTranscript)
        ProcessStep(title: "要点と行動を整理", isComplete: false, isCurrent: isOrganizing)
      }
    }
    .padding(18)
    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var primaryText: String {
    switch meeting.status {
    case .importing:
      "音声を読み込んでいます"
    case .transcribing:
      "会話を文字にしています"
    case .organizing(let detail):
      detail
    default:
      "内容を整理しています"
    }
  }

  private var hasTranscript: Bool {
    !meeting.transcript.isEmpty
  }

  private var isOrganizing: Bool {
    if case .organizing = meeting.status { return true }
    return false
  }
}

private struct ProcessStep: View {
  var title: String
  var isComplete: Bool
  var isCurrent: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isComplete ? "checkmark.circle.fill" : isCurrent ? "circle.dotted" : "circle")
        .foregroundStyle(isComplete ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      Text(title)
        .font(.subheadline)
        .foregroundStyle(isCurrent || isComplete ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
  }
}

private struct FailureOverview: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("処理を完了できませんでした", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("もう一度試す", systemImage: "arrow.clockwise", action: retry)
        .buttonStyle(.borderedProminent)
    }
  }
}

private struct PartialFailureBanner: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("文字起こしは使えます", systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("AI整理だけ再試行", systemImage: "arrow.clockwise", action: retry)
        .font(.subheadline.weight(.semibold))
    }
    .padding(16)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private struct RenameMeetingSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meeting: Meeting
  @State private var title: String

  init(meeting: Meeting) {
    self.meeting = meeting
    _title = State(initialValue: meeting.title)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("会議名", text: $title)
      }
      .navigationTitle("名前を変更")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            model.renameMeeting(meeting.id, title: title)
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
  }
}
