#if DEBUG
import SwiftUI

/// Debug-only look at the recorded timings, so a change can be compared with
/// the build it was made against. It shows names and numbers only.
struct PerformanceLogView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MemoraModel.self) private var model
  private var log: PerformanceLog { .shared }

  var body: some View {
    NavigationStack {
      List {
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
      .navigationTitle("計測")
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
