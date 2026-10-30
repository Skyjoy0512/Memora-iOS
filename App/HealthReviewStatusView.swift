import SwiftUI

struct HealthReviewStatusView: View {
  var loader: HealthReviewLoader
  var period: ReviewPeriod
  var reload: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("健康と活動").font(.headline)
        Spacer()
        Button("再読み込み", icon: .arrowClockwise, action: reload)
          .font(.subheadline)
          .frame(minHeight: 44)
          .disabled(loader.isLoading)
      }
      if loader.isLoading { ProgressView("健康データを更新しています") }
      if loader.period == period, let snapshot = loader.snapshot {
        if snapshot.hasData {
          Text("歩数: \(snapshot.stepCount.map { $0.formatted() + "歩" } ?? "取得できたデータなし")")
          Text("睡眠記録の合計: \(snapshot.sleepDuration.map { MemoraFormat.duration($0) } ?? "取得できたデータなし")")
          Text("ワークアウトの記録時間: \(snapshot.workoutDuration.map { MemoraFormat.duration($0) } ?? "取得できたデータなし")")
        } else {
          Text("取得できた健康データはありません。記録と読み取り許可をヘルスケアで確認してください。")
        }
      }
      if loader.period == period, let error = loader.errorMessage { Text(error).foregroundStyle(.secondary) }
      if loader.period == period, let updatedAt = loader.updatedAt {
        Text("最終取得: \(updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP"))))")
          .font(.caption).foregroundStyle(.secondary)
      }
      Text("データなしと読み取り不許可は区別できません。端末内でのみ表示し、AIや共有には渡しません。")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .font(.subheadline)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
