import SwiftUI

struct CompanyPresentationPreviewContent: View {
  var preview: CompanyPresentationPreview

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MemoraSpacing.section) {
        Text("追加ページのみを表示しています。原本の\(preview.originalPageCount)ページは表示・PDFに含みません。")
          .font(.footnote).foregroundStyle(.secondary)
        ForEach(preview.pages.enumerated(), id: \.element.id) { index, page in
          VStack(alignment: .leading, spacing: MemoraSpacing.md) {
            Text("追加ページ \(index + 1) / \(preview.pages.count)")
              .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            SlideView(page: page)
            DisclosureGroup {
              Text(([page.title] + (page.readingText ?? []) + [page.notes]).filter { !$0.isEmpty }.joined(separator: "\n\n"))
                .memoraReadingText().textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("テキストとノートを読む").frame(minHeight: MemoraSpacing.touchTarget) }
            .font(.subheadline)
          }
        }
      }
      .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
      .padding(MemoraSpacing.screen)
      .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}
