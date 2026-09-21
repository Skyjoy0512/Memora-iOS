#if DEBUG
import SwiftUI

/// Debug-only look at the recorded timings, so a change can be compared with
/// the build it was made against. It shows names and numbers only.
struct PerformanceLogView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MemoraModel.self) private var model
  @State private var isMeasuring = false
  @State private var measurementNote: String?
  private var log: PerformanceLog { .shared }

  var body: some View {
    NavigationStack {
      List {
        Section {
          if SelfChecks.results.isEmpty {
            Text("自己チェックはまだ実行されていません。")
              .foregroundStyle(.secondary)
          } else {
            ForEach(SelfChecks.results) { result in
              Label {
                VStack(alignment: .leading, spacing: 2) {
                  Text(result.name)
                  if let detail = result.detail {
                    Text(detail)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              } icon: {
                Image(systemName: result.passed ? "checkmark.circle" : "xmark.circle")
                  .foregroundStyle(result.passed ? Color.green : Color.red)
              }
              .accessibilityLabel("\(result.name): \(result.passed ? "成功" : "失敗")")
            }
          }
        } header: {
          Text("自己チェック（ビルド \(Bundle.main.appVersion)）")
        } footer: {
          Text("失敗しても処理は続きます。これはテストの証拠ではなく、実行の記録です。")
        }

        if log.entries.isEmpty {
          ContentUnavailableView(
            "まだ計測がありません",
            systemImage: "stopwatch",
            description: Text("起動・検索・保存・画像表示・処理を通ると記録されます。")
          )
        }

        ForEach(log.names, id: \.self) { name in
          if let stats = log.stats(for: name) {
            Section(name) {
              row("回数", "\(stats.samples)")
              row("中央値", milliseconds(stats.median))
              row("p95", milliseconds(stats.p95))
              row("最大", milliseconds(stats.maximum))
            }
          }
        }

        Section {
          Button("計測を実行（検索20回）", systemImage: "play") {
            Task { await runMeasurement() }
          }
          .disabled(isMeasuring)

          if let measurementNote {
            Text(measurementNote)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          Button("計測用に100件を追加", systemImage: "plus") {
            model.addMeasurementRecords(100)
          }
          Button("計測用に1,000件を追加", systemImage: "plus") {
            model.addMeasurementRecords(1_000)
          }
          Button("計測用データを削除", systemImage: "trash", role: .destructive) {
            model.removeMeasurementRecords()
          }
        } header: {
          Text("検証データ")
        } footer: {
          Text("音声・要約・文字起こしの無い、番号だけの記録です。計測が終わったら削除できます。")
        }

        if let latest = log.entries.last {
          Section("記録した環境") {
            row("ビルド", latest.build)
            row("端末", latest.device)
          }
        }
      }
      .navigationTitle("計測と自己チェック")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("消去", role: .destructive) { log.reset() }
        }
      }
    }
  }

  /// Runs the search path over whatever is loaded, so the log holds a sample
  /// worth reading a p95 from. It measures the matching pass, not the view
  /// render that follows it.
  private func runMeasurement() async {
    guard !isMeasuring else { return }
    isMeasuring = true
    measurementNote = "計測中…"
    defer { isMeasuring = false }

    let filters = SearchFilters()
    for _ in 0..<20 {
      _ = model.searchMeetings(matching: "計測用", filters: filters)
      await Task.yield()
    }
    model.persistMeetings()
    measurementNote = "\(model.meetings.count)件で検索20回と保存1回を記録しました"
  }

  private func row(_ title: String, _ value: String) -> some View {
    LabeledContent(title, value: value)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(title): \(value)")
  }

  private func milliseconds(_ value: Double) -> String {
    String(format: "%.1f ms", value)
  }
}
#endif
