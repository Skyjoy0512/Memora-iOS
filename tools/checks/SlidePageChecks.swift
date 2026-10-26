import CoreText
import Foundation

@main struct SlidePageChecks {
  static func main() throws {
    let samples = [
      DocumentSlide(title: "報告", bullets: []),
      DocumentSlide(title: "決まったこと", bullets: ["次回に確認", "予算は据え置き"], notes: "話す内容\n根拠: 資料1"),
      DocumentSlide(title: String(repeating: "長い見出し😀", count: 100), bullets: []),
      DocumentSlide(title: String(repeating: "長い本文見出し", count: 100), bullets: ["本文は欠かさない"]),
      DocumentSlide(title: "長い要点", bullets: [String(repeating: "日本語、留保・条件を残す。👨‍👩‍👧‍👦e\u{301} ", count: 180), "後続の要点"]),
      DocumentSlide(title: "明示改行", bullets: ["\n最初\r\n次の行\n\n末尾\n", "", "同じ内容", "同じ内容"]),
      DocumentSlide(title: "連続英数字", bullets: [String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789", count: 120)]),
      DocumentSlide(title: "多数の要点", bullets: (0..<100).map { "要点\($0): 条件付きで検討する" })
    ]
    var total = 0
    for slide in samples {
      let pages = SlidePageLayout.pages(for: slide)
      total += pages.count
      precondition(!pages.isEmpty && pages == SlidePageLayout.pages(for: slide))
      precondition(Set(pages.map(\.id)).count == pages.count)
      precondition(pages.allSatisfy { $0.sourceID == slide.id })
      precondition(pages.map(\.notes).filter { !$0.isEmpty } == (slide.notes.isEmpty ? [] : [slide.notes]))
      let headings = pages.prefix(while: { $0.bullets.isEmpty }).map(\.title).joined()
      if slide.bullets.isEmpty { precondition(headings == slide.title) }
      for index in slide.bullets.indices {
        let pieces = pages.flatMap(\.bullets).filter { $0.sourceIndex == index }
        precondition(pieces.map(\.text).joined() == slide.bullets[index], "lost or duplicated source text")
        precondition(pieces.filter(\.showsMarker).count == 1)
        if pieces.count > 1 {
          let count = SlidePageLayout.lines(slide.bullets[index], size: SlidePageLayout.bulletSize,
                                           width: SlidePageLayout.contentWidth - SlidePageLayout.bulletIndent).count
          precondition(CGFloat(count) * SlidePageLayout.bulletLineHeight > SlidePageLayout.bodyHeight)
        }
      }
      for page in pages {
        let height = page.isCover ? SlidePageLayout.coverTitleHeight : SlidePageLayout.titleHeight
        let lineHeight = page.isCover ? SlidePageLayout.coverLineHeight : SlidePageLayout.titleLineHeight
        precondition(CGFloat(page.titleLines.count) * lineHeight <= height)
        let body = page.bullets.reduce(CGFloat.zero) { $0 + CGFloat($1.lines.count) * SlidePageLayout.bulletLineHeight }
          + CGFloat(max(0, page.bullets.count - 1)) * SlidePageLayout.bulletGap
        precondition(body <= SlidePageLayout.bodyHeight)
        precondition(Set(page.bullets.map(\.id)).count == page.bullets.count)
        // Every fragment ends on a Character boundary in the original source.
        for bullet in page.bullets {
          for line in bullet.lines where !line.isEmpty {
            precondition(!line.unicodeScalars.first!.properties.isJoinControl)
          }
        }
      }
    }
    let empty = MemoraDocument(title: "空の資料", kind: .slides)
    precondition(SlidePageLayout.pages(for: empty).count == 1)
    precondition(SlidePageLayout.pages(for: empty).map(\.id) == SlidePageLayout.pages(for: empty).map(\.id))
    let old = try JSONDecoder().decode(DocumentSlide.self, from: JSONEncoder().encode(samples[1]))
    precondition(old == samples[1])
    let doc = MemoraDocument(title: "日本語・長文の検証", kind: .slides, slides: samples)
    let data = PPTXWriter.data(for: doc)
    let archive = try OfficeArchiveReader(data: data)
    precondition(archive.partNames.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }.count == total)
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try data.write(to: root.appendingPathComponent("pagination.pptx"))
    let expected = SlidePageLayout.pages(for: doc).map { page in
      ["title": page.titleLines.map(SlidePageLayout.visibleLine),
       "bullets": page.bullets.flatMap { $0.lines.map(SlidePageLayout.visibleLine) }]
    }
    try JSONSerialization.data(withJSONObject: expected).write(to: root.appendingPathComponent("pages.json"))
    print("SlidePageChecks: passed (\(samples.count) cases, \(total) derived pages; lossless ordered text, graphemes, intact points, notes, geometry, identity, old codec and real PPTX)")
  }
}
