import CoreText
import Foundation

/// One geometry and line-breaking policy for screen, PDF and editable OOXML.
enum SlidePageLayout {
  static let size = CGSize(width: 960, height: 540)
  static let margin: CGFloat = 54
  static let contentWidth: CGFloat = 852
  static let titleTop: CGFloat = 32
  static let titleHeight: CGFloat = 120
  static let titleSize: CGFloat = 32
  static let titleLineHeight: CGFloat = 40
  static let bodyTop: CGFloat = 184
  static let bodyHeight: CGFloat = 302
  static let bulletSize: CGFloat = 24
  static let bulletLineHeight: CGFloat = 34
  static let bulletGap: CGFloat = 14
  static let bulletIndent: CGFloat = 28
  static let coverTitleTop: CGFloat = 108
  static let coverTitleHeight: CGFloat = 324
  static let coverTitleSize: CGFloat = 44
  static let coverLineHeight: CGFloat = 58
  static let regularFont = "HelveticaNeue"
  static let boldFont = "HelveticaNeue-Bold"

  static func pages(for document: MemoraDocument) -> [SlidePage] {
    let slides = document.slides.isEmpty
      ? [DocumentSlide(id: document.id, title: document.displayTitle, bullets: [])]
      : document.slides
    return slides.flatMap { pages(for: $0) }
  }

  static func pages(for slide: DocumentSlide) -> [SlidePage] {
    let isCover = slide.isTitleSlide
    let headingLines = lines(slide.title, size: isCover ? coverTitleSize : titleSize,
                             width: contentWidth, bold: true)
    let titleCapacity = Int((isCover ? coverTitleHeight : titleHeight) / (isCover ? coverLineHeight : titleLineHeight))
    var pages: [SlidePage] = []
    var titleStart = 0
    // Very long headings get their own pages instead of shrinking or clipping.
    while headingLines.count - titleStart > titleCapacity {
      pages.append(SlidePage(sourceID: slide.id, fragment: pages.count,
        titleLines: Array(headingLines[titleStart..<(titleStart + titleCapacity)]),
        bullets: [], notes: "", isCover: isCover))
      titleStart += titleCapacity
    }
    let title = Array(headingLines.dropFirst(titleStart))
    var page = SlidePage(sourceID: slide.id, fragment: pages.count,
                         titleLines: title, bullets: [], notes: "", isCover: isCover)
    var used: CGFloat = 0
    for (index, bullet) in slide.bullets.enumerated() {
      let wrapped = lines(bullet, size: bulletSize, width: contentWidth - bulletIndent)
      var start = 0
      while start < wrapped.count {
        let gap: CGFloat = page.bullets.isEmpty ? 0 : bulletGap
        let capacity = Int((bodyHeight - used - gap) / bulletLineHeight)
        let remaining = wrapped.count - start
        // Keep a point intact when it fits on a fresh page. Split only points
        // longer than a full page, preserving their text and original ordering.
        if capacity == 0 || (start == 0 && remaining > capacity && CGFloat(remaining) * bulletLineHeight <= bodyHeight) {
          pages.append(page)
          page = SlidePage(sourceID: slide.id, fragment: pages.count,
                           titleLines: title, bullets: [], notes: "", isCover: false)
          used = 0
          continue
        }
        let count = min(remaining, capacity)
        page.bullets.append(SlidePage.Bullet(sourceIndex: index, firstLine: start,
                                           lines: Array(wrapped[start..<(start + count)])))
        used += gap + CGFloat(count) * bulletLineHeight
        start += count
      }
    }
    pages.append(page)
    pages[0].notes = slide.notes
    return pages
  }

  static func lines(_ text: String, size: CGFloat, width: CGFloat, bold: Bool = false) -> [String] {
    guard !text.isEmpty else { return [""] }
    let font = CTFontCreateWithName((bold ? boldFont : regularFont) as CFString, size, nil)
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let source = text as NSString
    var offset = 0
    var result: [String] = []
    while offset < source.length {
      // A small horizontal reserve accommodates Office font substitution.
      let suggested = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width * 0.94))
      let count = max(1, min(suggested, source.length - offset))
      let range = source.rangeOfComposedCharacterSequences(for: NSRange(location: offset, length: count))
      result.append(source.substring(with: range))
      offset = NSMaxRange(range)
    }
    return result
  }

  static func visibleLine(_ line: String) -> String {
    // Breaks stay in derived text for lossless reconstruction, but are
    // rendered by line positions / DrawingML breaks rather than twice.
    line.trimmingCharacters(in: .newlines)
  }
}
