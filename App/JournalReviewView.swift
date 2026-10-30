import SwiftUI

struct JournalReviewView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  var date: Date
  @State private var weekly = false
  @State private var healthLoader = HealthReviewService.makeLoader()
  @State private var healthRefreshID = 0
  @State private var savedDocument: MemoraDocument?
  @State private var saveError: String?
  @AppStorage("memora.journal.healthReviewEnabled") private var healthEnabled = false

  private var period: ReviewPeriod { weekly ? .week(date) : .day(date) }

  var body: some View {
    let period = period
    let healthRequest = JournalHealthRequest(period: period, enabled: healthEnabled,
      teamID: model.currentTeamID, isActive: scenePhase == .active, isReviewPresented: false,
      refreshID: healthRefreshID)
    let ownTasks = model.tasks.filter { model.isOwnTask($0) }
    let statistics = ReviewStatistics.build(period: period, meetings: model.meetings, tasks: ownTasks, entries: model.lifeLogEntries)
    let previous = previousPeriod(period)
    let previousStatistics = ReviewStatistics.build(period: previous, meetings: model.meetings, tasks: ownTasks, entries: model.lifeLogEntries)
    let places = model.lifeLogEntries.filter {
      $0.kind == .location && period.contains($0.occurredAt) && !SampleContent.isSample(lifeLogEntry: $0)
    }.sorted { $0.occurredAt < $1.occurredAt }
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Picker("振り返る期間", selection: $weekly) {
            Text("この日").tag(false)
            Text("この週").tag(true)
          }
          .pickerStyle(.segmented)

          MarkdownDocumentView(markdown: statistics.markdown(includesLocation: true))

          if !places.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("記録された場所").font(.headline)
              ForEach(places) { entry in
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.locationName ?? entry.title)
                  Text(entry.occurredAt.formatted(Date.FormatStyle(date: weekly ? .abbreviated : .omitted, time: .shortened).locale(Locale(identifier: "ja_JP"))))
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
              Text("場所の記録はこの画面で確認するためのものです。滞在の目的や気分は推測しません。")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }

          VStack(alignment: .leading, spacing: 12) {
            Text(weekly ? "前週との比較" : "前日との比較").font(.headline)
            Text("比較対象: \(previous.label)").font(.caption).foregroundStyle(.secondary)
            Text("会議・録音 \(statistics.meetingCount)件 / 前回 \(previousStatistics.meetingCount)件")
            Text("完了タスク \(statistics.completedTaskCount)件 / 前回 \(previousStatistics.completedTaskCount)件")
            if period.end > .now {
              Text("選んだ期間はまだ終わっていません。全期間の比較ではありません。")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }

          if model.currentTeamID == nil {
            healthSection
          }

          VStack(alignment: .leading, spacing: 12) {
            Text("自分に問いかける").font(.headline)
            Text("よかったことは？\n気になったことは？\n次に続けたいことは？")
              .lineSpacing(7)
            Button("\(weekly ? "週" : "日")の振り返りを資料に保存", icon: .docText) {
              save(statistics)
            }
            .buttonStyle(.bordered)
            Text("健康データと位置情報は資料に含めません。自分のメモは保存した資料で追記できます。")
              .font(.footnote).foregroundStyle(.secondary)
            if let saveError { Text(saveError).foregroundStyle(.secondary) }
          }
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(MemoraSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .background(MemoraPalette.background)
      .navigationTitle("振り返り")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .sheet(item: $savedDocument) { document in
        NavigationStack {
          DocumentDetailView(documentID: document.id)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                ToolbarIconButton("閉じる", icon: .xmark) { savedDocument = nil }
              }
            }
        }
      }
    }
    .task(id: healthRequest) {
      guard healthRequest.canRead else { healthLoader.clear(); return }
      await healthLoader.load(period, requestsAccess: true)
    }
    .onDisappear { healthLoader.clear() }
  }

  private var healthSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("健康データを振り返りに使う", isOn: $healthEnabled)
      Text("歩数・睡眠・ワークアウトを読み取り専用で使います。この画面内だけで表示し、AI・チーム・Webhook・バックアップには渡しません。")
        .font(.footnote).foregroundStyle(.secondary)
      if healthEnabled {
        HealthReviewStatusView(loader: healthLoader, period: period) { healthRefreshID += 1 }
        Text("睡眠・運動の重複した時間は1回として集計します。運動の記録時間は休止を含む場合があります。健康状態の診断や原因の判定は行いません。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private func previousPeriod(_ period: ReviewPeriod) -> ReviewPeriod {
    let days = weekly ? 7 : 1
    let calendar = Calendar.current
    return ReviewPeriod(
      start: calendar.date(byAdding: .day, value: -days, to: period.start) ?? period.start,
      end: period.start
    )
  }

  private func save(_ statistics: ReviewStatistics) {
    saveError = nil
    let document = MemoraDocument(
      title: "\(weekly ? "週" : "日")の振り返り \(statistics.period.label)",
      kind: .document,
      markdown: statistics.markdown(includesLocation: false) + "\n\n## 自分の振り返り\n\n## 次に続けたいこと\n"
    )
    if model.addDocument(document) { savedDocument = document }
    else { saveError = "保存できませんでした。保存先を確認してください。" }
  }
}
