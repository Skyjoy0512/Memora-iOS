import SwiftUI

struct JournalSummaryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var readingLineSpacing = MemoraTypography.readingLineSpacing
  var date: Date
  @Binding var backdrops: JournalBackdropSelection
  var events: [JournalCalendarEvent] = []
  var health: HealthReviewSnapshot?
  @AppStorage("memora.journal.healthReviewEnabled") private var healthEnabled = false
  @State private var showsReview = false
  @State private var showsCreate = false
  @State private var openSource: JournalDecisionSource?

  var body: some View {
    let ownTasks = model.ownTasks
    let recap = JournalDailyRecap.build(date: date, meetings: model.meetings,
      tasks: ownTasks, entries: model.lifeLogEntries, spaces: model.spaces,
      people: model.people, events: events, health: healthEnabled && model.currentTeamID == nil ? health : nil)
    let decisionSources = Dictionary(grouping: recap.context.decisionSources, by: \.statement)
    let shareRecap = JournalDailyRecap.build(date: date, meetings: model.meetings,
      tasks: ownTasks, entries: model.lifeLogEntries, spaces: model.spaces,
      people: model.people, events: events)
    let shareText = ([date.formatted(date: .complete, time: .omitted), shareRecap.heading,
      shareRecap.narrative, shareRecap.context.metrics.joined(separator: " · "),
      shareRecap.context.decisions.isEmpty ? "" : "決まったこと\n" + shareRecap.context.decisions.joined(separator: "\n"),
      shareRecap.context.openQuestions.isEmpty ? "" : "引き継ぐ問い\n" + shareRecap.context.openQuestions.joined(separator: "\n")])
      .filter { !$0.isEmpty }.joined(separator: "\n\n")

    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MemoraSpacing.section) {
          VStack(alignment: .leading, spacing: 16) {
            Text(date.formatted(.dateTime.year().month().day().weekday(.wide)))
              .font(.subheadline.weight(.medium))
            JournalBackdropView(backdrop: backdrops.current)
              .frame(height: 112)
              .clipShape(RoundedRectangle(cornerRadius: MemoraRadius.card))
            Text(recap.heading)
              .font(MemoraTypography.screenTitle)
              .accessibilityAddTraits(.isHeader)
              .fixedSize(horizontal: false, vertical: true)
            Text(recap.narrative)
              .font(.body)
              .lineSpacing(readingLineSpacing)
              .fixedSize(horizontal: false, vertical: true)
            if !recap.context.metrics.isEmpty {
              Text(recap.context.metrics.joined(separator: " · "))
                .font(MemoraTypography.secondary)
                .foregroundStyle(MemoraPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          actionBar(shareText: shareText)
          .buttonBorderShape(.capsule)
          .controlSize(.large)

          divider

          decisionSection(recap.context.decisions, sources: decisionSources)
          contextSection("引き継ぐ問い", values: recap.context.openQuestions)
          contextSection("関連プロジェクト", values: recap.context.projects)
          contextSection("記録にタグ付けされた人物", values: recap.context.people)
          contextSection("記録された場所", values: recap.context.places)
          contextSection("この後・明日に向けて", values: recap.context.nextSteps)

          if !recap.items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
              Text(Calendar.current.isDateInToday(date) ? "今日のハイライト" : "この日のハイライト")
                .font(MemoraTypography.sectionHeading)
                .accessibilityAddTraits(.isHeader)
              ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                  ForEach(recap.items.prefix(6)) { item in
                    highlight(item)
                      .frame(width: typeSize.isAccessibilitySize ? 300 : 220)
                  }
                }
                .scrollTargetLayout()
              }
              .scrollTargetBehavior(.viewAligned)
              .scrollIndicators(.hidden)
            }
            divider
          }

          VStack(alignment: .leading, spacing: 14) {
            Text("記録から振り返る")
              .font(MemoraTypography.sectionHeading)
              .accessibilityAddTraits(.isHeader)
            Text(Calendar.current.isDateInToday(date)
              ? "今日はここまでの記録から、主な出来事をまとめています。記録が増えると、サマリーも更新されます。"
              : "保存された記録から、主な出来事をまとめています。詳しい振り返りでは、前日との比較も確認できます。")
              .font(MemoraTypography.secondary)
              .lineSpacing(5)
            Button("日・週の振り返りを詳しく見る", icon: .chartBar) {
              InteractionFeedback.shared.send(.tap)
              showsReview = true
            }
            .frame(minHeight: 44)
            .buttonStyle(.bordered)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.xxl)
        .padding(.bottom, MemoraSpacing.group)
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .background(MemoraPalette.background)
      .foregroundStyle(MemoraPalette.textPrimary)
      .tint(MemoraPalette.action)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Menu {
            Button("背景を変更", icon: .arrowClockwise) {
              backdrops.shuffle(date)
              InteractionFeedback.shared.send(.selection)
            }
            Button("詳しい振り返り", icon: .chartBar) {
              InteractionFeedback.shared.send(.tap)
              showsReview = true
            }
          } label: {
            Label("その他", icon: .ellipsis).labelStyle(.iconOnly)
          }
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
      }
      .sheet(isPresented: $showsReview) { JournalReviewView(date: date) }
      .sheet(item: $openSource) { source in
        NavigationStack {
          MeetingDetailView(meetingID: source.meetingID, initialPlaybackStart: source.timestamp,
            showsLocalPlaybackBar: true)
        }
      }
      .sheet(isPresented: $showsCreate) { LifeLogCreationSheet(date: Calendar.current.isDateInToday(date) ? .now : date) }
    }
  }

  @ViewBuilder private func actionBar(shareText: String) -> some View {
    actionLayout(shareText: shareText).buttonStyle(MemoraButtonStyle(emphasis: .secondary))
  }

  private func actionLayout(shareText: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) { actions(shareText: shareText) }
      VStack(alignment: .leading, spacing: 12) { actions(shareText: shareText) }
    }
  }

  @ViewBuilder private func actions(shareText: String) -> some View {
    ShareLink(item: shareText) { Label("共有", icon: .squareAndArrowUp) }
    Button("記録を追加", icon: .squareAndPencil) {
      InteractionFeedback.shared.send(.tap)
      showsCreate = true
    }
  }

  @ViewBuilder private func decisionSection(_ decisions: [String], sources: [String: [JournalDecisionSource]]) -> some View {
    if !decisions.isEmpty {
      VStack(alignment: .leading, spacing: 16) {
        Text("決まったこと").font(MemoraTypography.sectionHeading).accessibilityAddTraits(.isHeader)
        ForEach(Array(decisions.enumerated()), id: \.offset) { _, decision in
          VStack(alignment: .leading, spacing: 6) {
            Text(decision).font(MemoraTypography.readingBody).lineSpacing(readingLineSpacing).fixedSize(horizontal: false, vertical: true)
            ForEach(sources[decision] ?? []) { source in
              Button("記録を確認：\(source.title)", icon: .textBubble) {
                InteractionFeedback.shared.send(.tap)
                openSource = source
              }
              .font(MemoraTypography.secondary)
              .frame(minHeight: 44, alignment: .leading)
              .accessibilityHint(source.timestamp == nil ? "元のサマリーを開きます" : "本文が一致する発言を開き、音声があれば再生します")
            }
          }
        }
        Text("決定事項は保存されたサマリーから抜き出しています。内容は元の記録で確認できます。")
          .font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder private func contextSection(_ title: String, values: [String]) -> some View {
    if !values.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(MemoraTypography.sectionHeading).accessibilityAddTraits(.isHeader)
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          Text(value).font(MemoraTypography.readingBody).lineSpacing(readingLineSpacing).fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var divider: some View {
    Divider().accessibilityHidden(true)
  }

  private func highlight(_ item: JournalRecapHighlight) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(item.date.formatted(date: .omitted, time: .shortened), icon: item.icon)
        .font(.subheadline.weight(.medium))
      Text(item.title).font(.headline).lineLimit(3)
      Text(item.summary.isEmpty ? item.category : item.summary)
        .font(MemoraTypography.secondary)
        .lineSpacing(4)
        .lineLimit(4)
    }
    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    .padding(MemoraSpacing.card)
    .memoraCard()
    .accessibilityElement(children: .combine)
  }
}
