import SwiftUI

struct DocumentSlidesView: View {
  var document: MemoraDocument

  var body: some View {
    let pages = SlidePageLayout.pages(for: document)
    LazyVStack(alignment: .leading, spacing: MemoraSpacing.section) {
      ForEach(pages.enumerated(), id: \.element.id) { index, page in
        DocumentSlidePageView(page: page, number: index + 1, total: pages.count)
      }
    }
  }
}

private struct DocumentSlidePageView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var page: SlidePage
  var number: Int
  var total: Int

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      Text("\(number) / \(total)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(total)ページ中\(number)ページ")
      if dynamicTypeSize.isAccessibilitySize {
        SlideReadingContent(page: page)
      } else {
        SlideView(page: page)
        DisclosureGroup("テキストを読む") { SlideReadingContent(page: page) }
          .font(.subheadline)
      }
      if !page.notes.isEmpty {
        DisclosureGroup("発表者ノート") {
          Text(page.notes)
            .memoraReadingText()
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SlideReadingContent: View {
  var page: SlidePage

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      Text(page.title)
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
      ForEach(page.bullets) { bullet in
        Text(bullet.text).memoraReadingText()
      }
    }
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
