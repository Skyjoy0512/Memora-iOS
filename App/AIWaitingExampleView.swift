#if DEBUG
import SwiftUI

/// Exercises the actual status components without invoking an engine or store.
struct AIWaitingExampleView: View {
  @State private var state = State.waiting
  @State private var reducedMotion = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("表示専用の架空データです。外部通信・記録の変更は行いません。")
          .font(.footnote).foregroundStyle(.secondary)
        Picker("状態", selection: $state) {
          ForEach(State.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu)
        Toggle("シマーを休止（表示検証）", isOn: $reducedMotion)
        ThinkingTraceView(message: message, isWaitingForApproval: state == .approval, permitsShimmer: !reducedMotion)
        if state == .streaming { Text("本文の受信が始まりました。") }
        if state == .failed { Text("接続できませんでした。再試行できます。") }
        if state == .cancelled { Text("回答を停止しました。") }
        ConversationStatusLine(label: "確認を待っています（表示例）", isWaiting: true)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
    }
    .navigationTitle("AI待機表示")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var message: AIChatMessage {
    var message = Self.fixture
    message.isThinking = [.waiting, .streaming, .approval].contains(state)
    message.text = state == .streaming ? "本文" : ""
    return message
  }

  private static let fixture: AIChatMessage = {
    var message = AIChatMessage(role: .assistant, text: "", isThinking: true)
    message.isAgentReply = true
    message.agentSteps = [AgentStep(icon: .docText, title: "記録を確認")]
    return message
  }()

  private enum State: String, CaseIterable, Identifiable {
    case waiting = "本文待ち", streaming = "本文受信中", approval = "承認待ち"
    case completed = "完了", failed = "失敗", cancelled = "キャンセル"
    var id: Self { self }
  }
}
#endif
