import SwiftUI

struct AudioDiagnosticsView: View {
  @AppStorage(AudioProcessingDiagnostics.enabledKey) private var isEnabled = false
  @AppStorage(AudioProcessingDiagnostics.inspectSignalKey) private var inspectsSignal = false
  @State private var reports: [AudioDiagnosticReport] = []
  @State private var exportText = "[]"

  var body: some View {
    Form {
      Section {
        Toggle("音声処理を計測", isOn: $isEnabled)
          .accessibilityIdentifier("audio.diagnostics.enabled")
        Toggle("音声品質も測定", isOn: $inspectsSignal)
          .disabled(!isEnabled)
        Button("更新") { Task { await refresh() } }
        ShareLink("計測JSONを共有", item: exportText)
          .disabled(reports.isEmpty)
        Button("計測ログを消去", role: .destructive) {
          AudioProcessingDiagnostics.invalidateSessions()
          Task {
            await AudioDiagnosticArchive.shared.clear()
            await refresh()
          }
        }
      } footer: {
        Text("本文・音声・ファイル名・認証情報は記録しません。直近12処理を端末に保存します。品質測定は次の処理から適用され、音声を追加で読み取ります。計測は電池や処理時間に影響するため、比較する測定では同じ設定を使ってください。")
      }
      if reports.isEmpty {
        Section {
          Text("計測をオンにして録音や文字起こしを実行すると記録されます。")
            .foregroundStyle(.secondary)
        }
      }
      ForEach(reports) { report in
        Section(report.kind.rawValue) {
          LabeledContent("結果", value: report.outcome.rawValue)
          LabeledContent("処理時間", value: String(format: "%.2f秒", report.wallSeconds))
          if let seconds = report.audioSeconds {
            LabeledContent("原音声の長さ", value: String(format: "%.2f秒", seconds))
          }
          if let rtf = report.overallRTF {
            LabeledContent("全体RTF", value: String(format: "%.4f", rtf))
          }
          if let recognition = report.totals[AudioDiagnosticReport.Stage.recognition.rawValue], let rtf = recognition.rtf {
            LabeledContent("完了区間の認識RTF", value: String(format: "%.4f", rtf))
          }
          LabeledContent("再利用した区間", value: String(report.reusedChunks))
          if let bytes = report.sampledPeakFootprintBytes {
            LabeledContent("サンプル内の最大メモリ", value: ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory))
          }
          LabeledContent("環境", value: report.environment.isSimulator ? "シミュレーター" : report.environment.hardware)
        }
      }
      Section {
        Text("RTF＝処理秒÷音声秒。全体には待ち時間・コピー・変換・再開を含みます。認識RTFは今回完了した区間だけの値です。メモリはアプリ全体の採取値、電池と温度状態は端末全体の値です。OSが停止した間の値は取得できません。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("音声処理の計測")
    .navigationBarTitleDisplayMode(.inline)
    .task { await refresh() }
    .onChange(of: isEnabled) { _, _ in AudioProcessingDiagnostics.invalidateSessions() }
  }

  private func refresh() async {
    reports = await AudioDiagnosticArchive.shared.snapshot()
    exportText = await AudioDiagnosticArchive.shared.export()
  }
}
