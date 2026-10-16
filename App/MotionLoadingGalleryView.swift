#if DEBUG
import SwiftUI

/// Isolated presentation fixtures: no model, files, credentials or external requests.
struct MotionLoadingGalleryView: View {
  @State private var scenario = Scenario.fast
  @State private var sourceLoader = Self.makeLoader()
  @State private var requestID: UUID?
  @State private var streamID: UUID?
  @State private var text = ""
  @State private var isStreaming = false
  @State private var keyboardDraft = ""
  @FocusState private var isKeyboardFocused: Bool

  var body: some View {
    let load = sourceLoader.snapshot
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("架空データだけの表示検証です。記録の保存・外部通信は行いません。")
            .font(.footnote).foregroundStyle(.secondary)
          Text("検証用タイトル").font(.title2.bold())
          Picker("取得時間", selection: $scenario) {
            ForEach(Scenario.allCases) { value in Text(value.rawValue).tag(value) }
          }.pickerStyle(.menu)
          HStack {
            Button("取得を開始") { requestID = UUID() }
            Button("表示をリセット") {
              sourceLoader.stop()
              requestID = nil
              sourceLoader = Self.makeLoader()
            }
          }
          MemoraLoadingContainer(state: load.state, label: "検証用の本文を読み込んでいます…",
            activityID: load.activityID,
            failure: load.failure, retry: { requestID = UUID() }, cancel: { sourceLoader.stop(); requestID = nil }) {
            if let value = load.value?.first { Text(value.text).textSelection(.enabled) }
          }
          Divider()
          HStack {
            Button("本文の生成を確認") { streamID = UUID() }
            if isStreaming { Button("生成を停止") { streamID = nil } }
          }
          TextField("キーボード表示の検証（保存しません）", text: $keyboardDraft)
            .focused($isKeyboardFocused)
            .submitLabel(.done)
            .onSubmit { isKeyboardFocused = false }
            .accessibilityIdentifier("motion-loading-keyboard")
          AIResponseText(text: text, isStreaming: isStreaming)
          Color.clear.frame(height: 1).id(ConversationScrollFollowing.bottomID)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
      }
      .modifier(ConversationScrollFollowing(proxy: proxy, isBusy: isStreaming))
    }
    .navigationTitle("表示の検証")
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完了") { isKeyboardFocused = false }
      }
    }
    .task(id: requestID) {
      guard requestID != nil else { return }
      await sourceLoader.load(.init(sourceID: Self.fixtureID, reference: scenario.rawValue, retry: 0))
    }
    .task(id: streamID) {
      guard let request = streamID, !Task.isCancelled else { return }
      text = ""
      isStreaming = true
      defer { if streamID == request || streamID == nil { isStreaming = false } }
      do {
        let bytes = try SyntheticAIEventStream(text: Self.sample)
        _ = try await CloudTurnStreamReader.response(from: bytes, provider: .chatCompletions) { value in
          guard streamID == request, !Task.isCancelled else { return }
          text = value
        }
      } catch is CancellationError { }
      catch { if streamID == request { text = "検証用ストリームを読み取れませんでした。もう一度お試しください。" } }
    }
  }

  private enum Scenario: String, CaseIterable, Identifiable {
    case fast = "50ms", normal = "200ms", explained = "2秒", cancellable = "手動で停止", failed = "失敗"
    var id: Self { self }
    var delay: Duration {
      switch self {
      case .fast: .milliseconds(50)
      case .normal: .milliseconds(200)
      case .explained, .failed: .seconds(2)
      case .cancellable: .seconds(60)
      }
    }
  }

  private static let fixtureID = UUID()

  private static func makeLoader() -> ProjectSourceTextLoader {
    ProjectSourceTextLoader { reference in
      let scenario = Scenario(rawValue: reference) ?? .fast
      try await Task.sleep(for: scenario.delay)
      if scenario == .failed { throw CocoaError(.fileReadUnknown) }
      return [ProjectSourceText(text: "保存済みの検証用本文です。更新中もこの本文は残ります。")]
    }
  }

  private static let sample = """
  # 架空の会議

  これは表示の検証用本文です。実際の記録やAIを利用していません。

  - 担当と期限を確認する
  - 未決事項を次回へ残す

  > 記録の根拠だけを使います。

  | 項目 | 状態 |
  | --- | --- |
  | 表示 | 検証中 |
  | 保存 | 実行しません |

  ```swift
  let message = "検証用"
  // # ここは見出しになりません
  ```

  """ + (1...12).map { "## 検証段落\($0)\n\n日本語の長文とスクロール位置を確認するための架空の段落です。既存の文章は再リビールしません。\n\n" }.joined()
}
#endif
