import SwiftUI
import QuickLook

#if DEBUG
struct DocumentRevisionExampleView: View {
  @State private var export: URL?
  @State private var preview: URL?
  @State private var error: String?
  @State private var companyFormat = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("編集後の資料と生成済みファイル")
          .font(.title2.bold())
        Text("架空データの表示確認です。記録の保存・変更や外部通信は行いません。")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Toggle("会社テンプレートの資料", isOn: $companyFormat)
        if let export {
          DocumentArtifactFileView(document: sample, url: export) { preview = export }
        }
        if let error { Text(error).foregroundStyle(.secondary) }
        MarkdownDocumentView(markdown: sample.markdown)
      }
      .padding(MemoraSpacing.screen)
      .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("資料の編集と版管理")
    .navigationBarTitleDisplayMode(.inline)
    .quickLookPreview($preview)
    .task {
      guard export == nil else { return }
      do { export = try DOCXWriter.write(Self.original) }
      catch { self.error = "検証用ファイルを作成できませんでした。" }
    }
    .onDisappear {
      if let export { ArtifactExportFile.removeTemporary([export]); self.export = nil }
    }
  }

  private var sample: MemoraDocument {
    var sample = Self.original.editing(title: "提案の修正版", body: "## 編集後の本文\n\n予算はまだ決まっていません。次回の会議で確認します。")!
    sample.companyTemplateID = companyFormat ? UUID(uuidString: "00000000-0000-0000-0000-000000000001") : nil
    return sample
  }

  private static let original = MemoraDocument(title: "編集前の提案", kind: .document,
    markdown: "## 元の本文\n\n予算は未定です。", artifactFileReference: "example.docx", artifactFormat: "DOCX")
}
#endif
