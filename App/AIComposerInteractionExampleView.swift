#if DEBUG
import SwiftUI

/// Submission callbacks are local spies; the production composer keeps its native input path.
struct AIComposerInteractionExampleView: View {
  @State private var text = "送信前の架空ドラフト"
  @State private var attachment: AIAttachment?
  @State private var input = ComposerInputState()
  @State private var isRunning = false
  @State private var acceptsSubmission = false
  @State private var submissions = 0
  @State private var stops = 0
  @State private var lastAction = "未操作"

  var body: some View {
    Form {
      Section {
        Text("送信・停止はこの画面内の確認だけです。AIや外部APIを呼び出さず、会話のドラフトも変更しません。")
          .font(.footnote).foregroundStyle(.secondary)
        Toggle("回答中として表示", isOn: $isRunning)
        Toggle("送信を受け付ける", isOn: $acceptsSubmission)
        Button("長文の架空ドラフトを入れる") {
          text = (1...10).map { "確認事項\($0): 読者、構成、費用、次回の相談で確認したい内容を整理します。" }.joined(separator: "\n")
        }
        Button("架空の添付を追加") {
          attachment = AIAttachment(id: UUID(), name: "表示確認.md", url: URL(fileURLWithPath: "/unused-composer-fixture.md"))
        }
      }
      Section("確認結果") {
        LabeledContent("送信の試行", value: submissions.formatted())
        LabeledContent("停止の操作", value: stops.formatted())
        LabeledContent("最後の操作", value: lastAction)
        LabeledContent("添付", value: attachment?.name ?? "なし")
        LabeledContent("未確定の入力", value: input.value?.hasMarkedText == true ? "あり" : "なし")
        Text(text.isEmpty ? "入力は空です" : text).textSelection(.enabled)
          .accessibilityLabel("確認中のドラフト").accessibilityValue(text)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      AIComposerBar(text: $text, attachment: $attachment, placeholder: "確認用の入力",
        isBusy: isRunning, onStop: isRunning ? stop : nil, keepsFocusAfterSubmit: true,
        onSubmit: { _ in
          submissions += 1
          lastAction = acceptsSubmission ? "送信受付" : "送信拒否・入力を保持"
          return acceptsSubmission
        }, mentionInput: input)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
    .navigationTitle("コンポーザーの操作確認").navigationBarTitleDisplayMode(.inline)
  }

  private func stop() {
    stops += 1
    isRunning = false
    lastAction = "停止・入力を保持"
  }
}
#endif
