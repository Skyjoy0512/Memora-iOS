import SwiftUI
import QuickLook

#if DEBUG
struct DocumentPDFExportExampleView: View {
  @State private var export = DocumentPDFExportSession()
  @State private var preview: URL?
  @State private var file: URL?
  @State private var failure: String?

  var body: some View {
    List {
      Section {
        Text("架空の文章と表だけを使います。記録の保存・外部通信は行いません。生成ファイルはプレビューを閉じると削除します。")
        Button("改ページのPDFを作成") { generate(stress: false) }
        Button("長文で進行と取消を確認") { generate(stress: true) }
      }
    }
    .disabled(export.isRunning)
    .accessibilityHidden(export.isRunning)
    .overlay {
      if let progress = export.progress {
        ZStack {
          Color.black.opacity(0.08).ignoresSafeArea().accessibilityHidden(true)
          DocumentPDFExportProgressView(progress: progress) { export.cancel() }
        }
      }
    }
    .navigationTitle("PDFの改ページと取消")
    .navigationBarTitleDisplayMode(.inline)
    .quickLookPreview($preview)
    .onChange(of: preview) { _, value in
      if value == nil { cleanUp() }
    }
    .onDisappear {
      export.cancel()
      if preview == nil { cleanUp() }
    }
    .alert("書き出せませんでした", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
      Button("閉じる", role: .cancel) {}
    } message: { Text(failure ?? "") }
  }

  private func generate(stress: Bool) {
    cleanUp()
    let paragraphs = (1...(stress ? 20_000 : 32)).map { index in
      "段落\(index)。記録された事実と未確認の提案を区別します。担当者・期限・数値を勝手に補いません。改ページ後も内容を省略せず、確認した条件を維持します。"
    }.joined(separator: "\n\n")
    let rows = (1...45).map { "| 項目\($0) | 改ページでも行の途中を切らず、確認した内容を保ちます。 | 未定 |" }.joined(separator: "\n")
    let document = MemoraDocument(title: "架空のPDF検証・保存しません", kind: .document,
      markdown: "## 文章の確認\n\n" + paragraphs + "\n\n## 表の確認\n\n| 項目 | 内容 | 期限 |\n| --- | --- | --- |\n" + rows + "\n\n本文の最後まで確認できました。")
    export.start(document: document, isCurrent: { true }, completed: { url in
      file = url
      preview = url
    }, failed: { failure = $0 })
  }

  private func cleanUp() {
    if let file { ArtifactExportFile.removeTemporary([file]) }
    file = nil
  }
}
#endif
