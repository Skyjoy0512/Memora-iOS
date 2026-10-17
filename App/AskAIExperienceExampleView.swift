#if DEBUG
import SwiftUI

/// Render-only fixtures never enter the conversation, SQLite or a provider.
struct AskAIExperienceExampleView: View {
  @State private var displayed = ""
  @State private var isStreaming = false
  @State private var streamTask: Task<Void, Never>?
  @State private var status = ExampleStatus.running

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("架空データの表示確認です。記録の保存や外部APIの実行は行いません。")
          .font(.footnote).foregroundStyle(.secondary)
        Picker("実行状態の例", selection: $status) {
          ForEach(ExampleStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu)
        AgentActivityView(steps: steps, isRunning: status == .running || status == .waiting, isWaiting: status == .waiting)
        VStack(alignment: .leading, spacing: 10) {
          Text("タスクの進捗（架空データ）").font(.headline)
          AIInterfaceTaskProgress(tasks: Self.tasks)
        }
        Button(isStreaming ? "表示を停止" : "部品単位の表示を再生", icon: isStreaming ? .stopFill : .playFill) {
          if isStreaming { streamTask?.cancel(); isStreaming = false }
          else { play() }
        }.frame(minHeight: 44)
        Button("完成した1部品を表示") {
          guard let next = Self.answer.range(of: ",{\"id\":\"notes\"") else { return }
          streamTask?.cancel()
          displayed = String(Self.answer[..<next.lowerBound]) + ",{\"id\":\"notes\""
          isStreaming = true
        }.frame(minHeight: 44)
        AIResponseText(text: displayed.isEmpty ? Self.answer : displayed, isStreaming: isStreaming)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
    }
    .navigationTitle("Ask AI 2.0の表示確認").navigationBarTitleDisplayMode(.inline)
    .onDisappear { streamTask?.cancel() }
  }

  private var steps: [AgentStep] {
    [AgentStep(icon: .magnifyingglass, title: "記録を検索", detail: "架空の記録2件", state: .done, query: "定例",
      results: [.init(title: "週次の相談", subtitle: "表示用の例")]),
     AgentStep(icon: .checklist, title: "未完了のタスクを整理", detail: status == .failed ? "取得できませんでした" : nil,
      state: status == .finished ? .done : status == .failed ? .failed : status == .stopped ? .declined : .running)]
  }

  private func play() {
    streamTask?.cancel(); displayed = ""; isStreaming = true
    streamTask = Task { @MainActor in
      let characters = Array(Self.answer)
      for end in stride(from: 24, through: characters.count + 23, by: 24) {
        guard !Task.isCancelled else { return }
        displayed = String(characters.prefix(min(end, characters.count)))
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard !Task.isCancelled else { return }
      isStreaming = false
    }
  }

  private static var tasks: [MemoraTask] {
    [MemoraTask(id: UUID(), title: "架空の作業A", isCompleted: true),
     MemoraTask(id: UUID(), title: "架空の作業B", isCompleted: false),
     MemoraTask(id: UUID(), title: "架空の作業C", isCompleted: false)]
  }

  private static let answer = """
  ## 今週の確認事項

  担当と期限は、確認できた範囲だけ整理します。

  | 項目 | 現在 | 次の確認 |
  | --- | --- | --- |
  | 提案の構成 | 検討中 | 読者を確認 |
  | 見積もり | 未確認 | 担当者へ確認 |

  ```swift
  let message = "表示用のコードです"
  print(message)
  ```

  ```memora-ui
  {"version":1,"components":[{"id":"schedule","kind":"Timeline","title":"次の予定（例）","items":[{"id":"a","title":"月曜日","detail":"構成の確認"}]},{"id":"notes","kind":"Disclosure","title":"未確認の事項","items":[{"id":"b","title":"期限と担当","detail":"元の記録で確認するまでは確定しません。"}]}]}
  ```
  """

  private enum ExampleStatus: String, CaseIterable {
    case running = "実行中", waiting = "確認待ち", finished = "終了", failed = "失敗", stopped = "停止"
  }
}
#endif
