#if DEBUG
import SwiftUI

struct NativeAIInterfaceExampleView: View {
  @State private var isStreaming = false
  @State private var displayed = ""
  @State private var streamTask: Task<Void, Never>?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("表示検証用の例です。実際の記録・AI回答ではありません。")
          .font(.footnote).foregroundStyle(.secondary)
        Button(isStreaming ? "表示を停止" : "ストリーミングを確認", icon: isStreaming ? .stopFill : .playFill) {
          if isStreaming { streamTask?.cancel(); isStreaming = false }
          else { play() }
        }
        .frame(minHeight: 44)
        AIResponseText(text: displayed.isEmpty ? Self.example : displayed, isStreaming: isStreaming)
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(18)
    }
    .background(MemoraPalette.background)
    .navigationTitle("構造化回答の表示確認").navigationBarTitleDisplayMode(.inline)
    .onDisappear { streamTask?.cancel() }
  }

  /// Replays the answer as a local string, so a component is drawn only once its
  /// JSON closes — the same path a real stream takes, with no model or network.
  private func play() {
    streamTask?.cancel()
    displayed = ""
    isStreaming = true
    streamTask = Task { @MainActor in
      for end in stride(from: 10, through: Self.example.count + 9, by: 10) {
        guard !Task.isCancelled else { return }
        displayed = String(Self.example.prefix(end))
        try? await Task.sleep(for: .milliseconds(60))
      }
      guard !Task.isCancelled else { return }
      isStreaming = false
    }
  }

  private static var example: String {
    """
    表・グラフ・日程をネイティブに表示します。この画面から外部送信やデータ変更は行いません。

    ```json-render
    {"root":"answer","elements":{
      "answer":{"type":"Stack","props":{},"children":["metric","comparison","chart","timeline","row"]},
      "metric":{"type":"Metric","props":{"items":[{"id":"total","title":"検証用の件数（件）","value":8,"detail":"架空の表示データ"}]},"children":[]},
      "comparison":{"type":"ComparisonTable","props":{"title":"選択肢の比較","columns":["候補","移動","過ごし方"],"items":[{"id":"a","cells":["候補A","徒歩","街歩き"]},{"id":"b","cells":["候補B","鉄道","美術館"]}]},"children":[]},
      "chart":{"type":"Chart","props":{"title":"表示検証用の件数","items":[{"id":"a","title":"例A","value":3},{"id":"b","title":"例B","value":5}]},"children":[]},
      "timeline":{"type":"Timeline","props":{"title":"日程の例","items":[{"id":"morning","title":"午前","detail":"目的地への移動と街歩き"},{"id":"afternoon","title":"午後","detail":"休憩と振り返り"}]},"children":[]},
      "row":{"type":"Row","props":{},"children":["left","right"]},
      "left":{"type":"Chart","props":{"title":"午前の件数","items":[{"id":"a","title":"例A","value":2}]},"children":[]},
      "right":{"type":"Chart","props":{"title":"午後の件数","items":[{"id":"b","title":"例B","value":4}]},"children":[]}
    }}
    ```
    """
  }
}
#endif
