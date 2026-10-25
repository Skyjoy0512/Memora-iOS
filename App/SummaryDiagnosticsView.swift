import SwiftUI

struct SummaryDiagnosticsView: View {
  @State private var reports: [String] = []

  var body: some View {
    MemoraList {
      Section {
        Text("直近12件の処理段階と経過時間です。本文・認証情報は含みません。アプリ終了前の記録はOSLogのSummaryTimelineで確認できます。")
          .font(.footnote).foregroundStyle(.secondary)
        Button("更新") { reports = SummaryDiagnostics.reports }
      }
      if reports.isEmpty {
        Text("この起動中の要約処理はまだありません。")
      }
      ForEach(reports.indices, id: \.self) { index in
        Section("処理 \(index + 1)") {
          Text(reports[index])
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .navigationTitle("要約の診断")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { reports = SummaryDiagnostics.reports }
  }
}
