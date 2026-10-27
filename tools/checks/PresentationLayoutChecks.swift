import CoreGraphics
import Foundation
import PDFKit
import AppKit

@main
struct PresentationLayoutChecks {
  static func main() throws {
    setbuf(stdout, nil)
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    precondition(SlideArchetype.allCases.count == 65)
    precondition(Set(SlideArchetype.allCases.map(\.upstreamID)).count == 65)
    let legacy = Data(#"{"id":"11111111-1111-1111-1111-111111111111","title":"旧資料","bullets":["元の要点"],"notes":"発表者ノート"}"#.utf8)
    let old = try JSONDecoder().decode(DocumentSlide.self, from: legacy)
    precondition(old.composition == nil && SlidePageLayout.pages(for: old).first?.elements == nil)
    var failures = 0
    var signatures = Set<[PresentationElement]>()
    for layout in SlideArchetype.allCases {
      let slide = PresentationExample.slide(layout)
      let issues = PresentationValidator.issues(for: slide)
      let errors = issues.filter(\.isError)
      if !errors.isEmpty {
        print("FAIL \(layout.rawValue): " + errors.map { "\($0.code) \($0.elementID ?? -1) \($0.message)" }.joined(separator: "; "))
        failures += 1
        continue
      }
      let elements = PresentationLayoutEngine.elements(for: slide)
      precondition(!elements.isEmpty)
      signatures.insert(elements)
      precondition(elements == PresentationLayoutEngine.elements(for: slide), "Non-deterministic geometry")
      let restored = try JSONDecoder().decode(DocumentSlide.self, from: JSONEncoder().encode(slide))
      precondition(slide == restored)
      var document = MemoraDocument(title: "検証 \(layout.rawValue)", kind: .slides, slides: [slide])
      precondition(document.editing(title: document.title, body: "# 破壊するアウトライン") == nil)
      let pptx = PPTXWriter.data(for: document)
      precondition(pptx == PPTXWriter.data(for: document))
      try pptx.write(to: output.appendingPathComponent(layout.rawValue + ".pptx"))
      let pdfURL = output.appendingPathComponent(layout.rawValue + ".pdf")
      var box = CGRect(x: 0, y: 0, width: 960, height: 540)
      let context = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
      context.beginPDFPage(nil)
      context.setFillColor(PresentationDrawing.color("FFFFFF")); context.fill(box)
      context.translateBy(x: 0, y: 540); context.scaleBy(x: 1, y: -1)
      PresentationDrawing.draw(elements, in: context)
      context.endPDFPage(); context.closePDF()
      let pdf = PDFDocument(url: pdfURL)!
      precondition(pdf.pageCount == 1 && (pdf.string ?? "").contains("判断"), "Japanese PDF text missing")
      let thumbnail = pdf.page(at: 0)!.thumbnail(of: NSSize(width: 960, height: 540), for: .mediaBox)
      let png = NSBitmapImageRep(data: thumbnail.tiffRepresentation!)!.representation(using: .png, properties: [:])!
      try png.write(to: output.appendingPathComponent(layout.rawValue + ".png"))
      let json = try JSONEncoder().encode(document)
      let restoredDocument = try JSONDecoder().decode(MemoraDocument.self, from: json)
      precondition(restoredDocument == document)
      document.slides[0].title = "編集後も数値と出典を保持"
      precondition(!PPTXWriter.data(for: document).isEmpty)
      // Empty payload must fail, never turn into a normal-looking bullet deck.
      let empty = DocumentSlide(title: "入力なし", bullets: [], composition: .init(layout: layout))
      if layout.input != .title { precondition(!PresentationValidator.inputIssues(for: empty).isEmpty) }
      print("PASS \(layout.rawValue) \(layout.upstreamID): model, geometry, PDF text, PPTX, roundtrip, edit, empty")
    }
    // Negative controls prove overflow, table shape, arithmetic and bounds checks fire.
    var invalid = PresentationExample.slide(.m08)
    invalid.composition?.chart?.series[0].values[3] = 120
    precondition(PresentationValidator.inputIssues(for: invalid).contains { $0.message.contains("着地") })
    invalid = PresentationExample.slide(.b09)
    invalid.composition?.table?.rows[0] = ["不正"]
    precondition(!PresentationValidator.inputIssues(for: invalid).isEmpty)
    invalid = PresentationExample.slide(.b01)
    invalid.title = String(repeating: "長い見出し", count: 28)
    precondition(PresentationValidator.issues(for: invalid).contains { $0.code == "overflow" })
    invalid = PresentationExample.slide(.m34)
    invalid.composition?.schedule?.entries[0].end = Int.max
    precondition(!PresentationValidator.inputIssues(for: invalid).isEmpty)
    _ = PresentationLayoutEngine.elements(for: invalid)
    invalid = PresentationExample.slide(.m06)
    invalid.composition?.chart?.series[0].values[0] = -1
    precondition(!PresentationValidator.inputIssues(for: invalid).isEmpty)
    let validInput: [String: Any] = ["title": "確認した課題を解決する", "bullets": [String](), "layout": "b26",
      "content_json": #"{"items":[{"heading":"現状","body":"次の作業"}],"sources":[{"title":"会議","locator":"資料1"}]}"#]
    let parsed = try PresentationToolInput.slide(validInput)
    precondition(parsed.composition?.layout == .b26 && parsed.composition?.items?.count == 1)
    for raw in ["{}", #"{"unknown":"data"}"#, #"{"layout":"b01"}"#] {
      var bad = validInput; bad["content_json"] = raw
      do { _ = try PresentationToolInput.slide(bad); preconditionFailure("Invalid input accepted") } catch {}
    }
    let ascending = PresentationElement(id: 0, kind: .line, x: 20, y: 30, width: 100, height: 20,
      points: [.init(x: 20, y: 50), .init(x: 120, y: 30)])
    let lineXML = PresentationOOXML.shapes([ascending])
    precondition(lineXML.contains("p:cxnSp") && lineXML.contains("flipV=\"1\""))
    let first = PresentationExample.slide(.m03)
    var conflicting = first; conflicting.id = UUID(); conflicting.composition?.metrics?[0].value = 99
    let conflictDocument = MemoraDocument(title: "出典内の不整合", kind: .slides, slides: [first, conflicting])
    precondition(PresentationValidator.issues(for: conflictDocument).contains { $0.code == "numberConflict" })
    let narrow = PresentationElement(id: 0, kind: .text, x: 0, y: 0, width: 1, height: 100, text: "👩🏽‍💻", fontSize: 30)
    precondition(PresentationText.widestLine(narrow) > narrow.width)
    print("Distinct geometry signatures: \(signatures.count)/65; failures: \(failures)")
    if failures > 0 { exit(1) }
    let catalog = MemoraDocument(title: "65型・架空データ検証", kind: .slides,
      slides: SlideArchetype.allCases.map { layout in
        var slide = PresentationExample.slide(layout)
        slide.title = "\(layout.rawValue) \(layout.title)"
        return slide
      })
    let start = ContinuousClock.now
    let catalogData = PPTXWriter.data(for: catalog)
    let elapsed = start.duration(to: .now)
    try catalogData.write(to: output.appendingPathComponent("catalog-65.pptx"))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(catalog).write(to: output.appendingPathComponent("catalog-65.json"))
    var mediaBox = CGRect(x: 0, y: 0, width: 960, height: 540)
    let catalogPDF = CGContext(output.appendingPathComponent("catalog-65.pdf") as CFURL, mediaBox: &mediaBox, nil)!
    for slide in catalog.slides {
      catalogPDF.beginPDFPage(nil); catalogPDF.saveGState()
      catalogPDF.setFillColor(PresentationDrawing.color("FFFFFF")); catalogPDF.fill(mediaBox)
      catalogPDF.translateBy(x: 0, y: 540); catalogPDF.scaleBy(x: 1, y: -1)
      PresentationDrawing.draw(PresentationLayoutEngine.elements(for: slide), in: catalogPDF)
      catalogPDF.restoreGState(); catalogPDF.endPDFPage()
    }
    catalogPDF.closePDF()
    print("65-page editable catalog: \(catalogData.count) bytes, PPTX generation \(elapsed) (host Debug; not device latency)")
  }
}
