import SwiftUI

#if DEBUG
struct CompanyPresentationPreviewExampleView: View {
  @State private var preview: CompanyPresentationPreview?
  @State private var failure: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("架空の会社書式と内容です。保存・外部送信は行いません。")
        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, MemoraSpacing.screen)
      if let preview { CompanyPresentationPreviewContent(preview: preview) }
      else if let failure { Text(failure).padding() }
      else { ShimmerText(text: "会社書式を確認しています") }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .navigationTitle("追加ページ・会社書式")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      do {
        let worker = Task.detached(priority: .userInitiated) {
          let base = PPTXWriter.data(for: .init(title: "架空の原本", kind: .slides, slides: [.init(title: "含まない原本ページ", bullets: [])]))
          var archive = try OfficeArchiveReader(data: base), output = ZipArchive()
          for path in archive.partNames {
            var text = String(decoding: try archive.read(path), as: UTF8.self)
            if path == "ppt/theme/theme1.xml" {
              text = text.replacingOccurrences(of: "<a:accent1><a:srgbClr val=\"0D0D0D\"/></a:accent1>", with: "<a:accent1><a:srgbClr val=\"005A50\"/></a:accent1>")
                .replacingOccurrences(of: "<a:accent2><a:srgbClr val=\"303030\"/></a:accent2>", with: "<a:accent2><a:srgbClr val=\"803300\"/></a:accent2>")
            }
            output.add(path, text: text)
          }
          return try CompanyPresentationPreview.make(document: .init(title: "架空の追加資料", kind: .slides,
            slides: [.m04, .m14, .b24].map { PresentationExample.slide($0) }), template: output.data())
        }
        preview = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      } catch { failure = error.localizedDescription }
    }
  }
}
#endif
