#if DEBUG
import SwiftUI

struct NativeAIInterfaceExampleView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("表示検証用の例です。実際の記録・AI回答ではありません。")
          .font(.footnote).foregroundStyle(.secondary)
        AIResponseText(text: Self.example)
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(18)
    }
    .background(MemoraPalette.background)
    .navigationTitle("構造化回答の表示確認").navigationBarTitleDisplayMode(.inline)
  }

  private static var example: String {
    """
    表・グラフ・日程をネイティブに表示します。この画面から外部送信やデータ変更は行いません。

    ```memora-ui
    {"version":1,"components":[
      {"id":"comparison","kind":"ComparisonTable","title":"選択肢の比較","columns":["候補","移動","過ごし方"],"items":[{"id":"a","cells":["候補A","徒歩","街歩き"]},{"id":"b","cells":["候補B","鉄道","美術館"]}]},
      {"id":"chart","kind":"Chart","title":"表示検証用の件数","items":[{"id":"a","title":"例A","value":3},{"id":"b","title":"例B","value":5}]},
      {"id":"timeline","kind":"Timeline","title":"日程の例","items":[{"id":"morning","title":"午前","detail":"目的地への移動と街歩き"},{"id":"afternoon","title":"午後","detail":"休憩と振り返り"}]},
      {"id":"row","kind":"Row","components":[
        {"id":"left","kind":"Chart","title":"午前の件数","items":[{"id":"a","title":"例A","value":2}]},
        {"id":"right","kind":"Chart","title":"午後の件数","items":[{"id":"b","title":"例B","value":4}]}
      ]}
    ]}
    ```
    """
  }
}
#endif
