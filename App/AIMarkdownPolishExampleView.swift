#if DEBUG
import SwiftUI

/// Both variants render the same synthetic content, without a model or network call.
struct AIMarkdownPolishExampleView: View {
  @State private var useAdaptedLayout = true
  @State private var isStreaming = false
  @State private var displayed = ""
  @State private var streamTask: Task<Void, Never>?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text("同じ架空の回答で表示を比較します。外部API・実データは使いません。")
          .font(.footnote).foregroundStyle(.secondary)
        Picker("回答の表示", selection: $useAdaptedLayout) {
          Text("従来").tag(false)
          Text("OSSを反映").tag(true)
        }.pickerStyle(.segmented)
        Button(isStreaming ? "表示を停止" : "ストリーミングを確認") {
          if isStreaming { streamTask?.cancel(); isStreaming = false }
          else { play() }
        }.frame(minHeight: 44)
        Text("今週の方針と、次に確認することを整理して")
          .font(.body).padding(14).aiBubble()
          .frame(maxWidth: .infinity, alignment: .trailing)
        if useAdaptedLayout {
          AIResponseText(text: displayed.isEmpty ? Self.answer : displayed, isStreaming: isStreaming)
        } else {
          AIMarkdownBaselineExampleView(text: Self.answer)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
    }
    .navigationTitle("OSSの部分移植")
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear { streamTask?.cancel() }
  }

  private func play() {
    streamTask?.cancel(); displayed = ""; isStreaming = true
    streamTask = Task { @MainActor in
      for end in stride(from: 12, through: Self.answer.count + 11, by: 12) {
        guard !Task.isCancelled else { return }
        displayed = String(Self.answer.prefix(end))
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard !Task.isCancelled else { return }
      isStreaming = false
    }
  }

  private static let answer = """
  ## 今週の方針

  読者が判断できる順番で、提案の構成と未確認事項を整理します。

  > 担当と期限は、記録で確認できた内容だけを記載します。

  | 項目 | 次に確認すること |
  | --- | --- |
  | 構成 | 提案の読者と期待する判断を確認 |
  | 見積もり | 範囲と追加費用を確認 |

  ```swift
  let title = "週次の提案"
  print(title)
  ```

  - 構成を先に確認する
  - 未確認の費用は確定と書かない
  """
}
#endif
