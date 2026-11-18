#if DEBUG
import SwiftUI

struct JSONRenderExampleView: View {
  @State private var mode = ExampleMode.form
  @State private var streaming = false
  @State private var displayed = ""
  @State private var replay: Task<Void, Never>?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("固定データの表示検証です。実際の記録ではありません。外部APIは使いません。")
          .font(.footnote).foregroundStyle(.secondary)
        Picker("表示形式", selection: $mode) {
          ForEach(ExampleMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
        }.pickerStyle(.segmented)
        Button(streaming ? "再生を停止" : "ストリーミングを確認", icon: streaming ? .stopFill : .playFill) {
          if streaming { replay?.cancel(); streaming = false; displayed = "" }
          else { play() }
        }.frame(minHeight: 44)
        AIResponseText(text: displayed.isEmpty ? example : displayed, isStreaming: streaming, animates: false)
          .id(mode)
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(18)
    }
    .background(MemoraPalette.background)
    .navigationTitle("生成UIの操作確認").navigationBarTitleDisplayMode(.inline)
    .onChange(of: mode) { _, _ in replay?.cancel(); streaming = false; displayed = "" }
    .onDisappear { replay?.cancel() }
  }

  private var example: String {
    let file = switch mode {
    case .form: "JSONRenderExample"
    case .patch: "JSONRenderPatchExample"
    case .yaml: "JSONRenderYAMLExample"
    case .long: "JSONRenderLongExample"
    }
    guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return "表示データを読み込めませんでした。" }
    return text
  }

  private func play() {
    replay?.cancel()
    let source = example
    displayed = ""
    streaming = true
    replay = Task { @MainActor in
      for end in stride(from: 48, through: source.count + 47, by: 48) {
        guard !Task.isCancelled else { return }
        displayed = String(source.prefix(end))
        try? await Task.sleep(for: .milliseconds(60))
      }
      guard !Task.isCancelled else { return }
      streaming = false
    }
  }

  private enum ExampleMode: String, CaseIterable, Identifiable {
    case form = "フォーム", patch = "JSON Patch", yaml = "YAML", long = "長文"
    var id: String { rawValue }
  }
}
#endif
