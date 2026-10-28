import AppKit
import PDFKit
import Foundation

@main struct CompanyPresentationPreviewChecks {
  static func main() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let images = output.appendingPathComponent("native", isDirectory: true)
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let base = PPTXWriter.data(for: .init(title: "原本", kind: .slides, slides: [.init(title: "含めない原本ページ", bullets: ["原本を変更しない"]) ]))
    let decoration = "<p:sp><p:nvSpPr><p:cNvPr id='40' name='Fictional mark'/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x='10160000' y='25400'/><a:ext cx='1270000' cy='203200'/></a:xfrm><a:prstGeom prst='rect'><a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val='accent1'/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>"
    let dark = decoration.replacingOccurrences(of: "id='40'", with: "id='41'").replacingOccurrences(of: "x='10160000'", with: "x='8636000'")
      .replacingOccurrences(of: "<a:schemeClr val='accent1'/>", with: "<a:schemeClr val='accent1'><a:lumMod val='50000'/></a:schemeClr>")
    let light = decoration.replacingOccurrences(of: "id='40'", with: "id='42'").replacingOccurrences(of: "x='10160000'", with: "x='7112000'")
      .replacingOccurrences(of: "<a:schemeClr val='accent1'/>", with: "<a:srgbClr val='005A50'><a:lumMod val='20000'/><a:lumOff val='80000'/></a:srgbClr>")
    let source = try changing(base) { path, value in
      if path == "ppt/slideMasters/slideMaster1.xml" { return value.replacingOccurrences(of: "</p:spTree>", with: decoration + dark + "</p:spTree>") }
      if path == "ppt/slideLayouts/slideLayout1.xml" { return value.replacingOccurrences(of: "</p:spTree>", with: light + "</p:spTree>") }
      if path == "ppt/theme/theme1.xml" { return value.replacingOccurrences(of: "<a:accent1><a:srgbClr val=\"0D0D0D\"/></a:accent1>", with: "<a:accent1><a:srgbClr val=\"005A50\"/></a:accent1>")
        .replacingOccurrences(of: "<a:accent2><a:srgbClr val=\"303030\"/></a:accent2>", with: "<a:accent2><a:srgbClr val=\"803300\"/></a:accent2>") }
      return value
    }
    try source.write(to: output.appendingPathComponent("source.pptx"))
    try CompanyPresentationColorChecks.run(source: source)
    try CompanyPresentationBackgroundChecks.run(source: source)
    let slides = SlideArchetype.allCases.map { PresentationExample.slide($0) }
    for slide in slides {
      let id = slide.composition!.layout.rawValue
      let document = MemoraDocument(title: "架空の追加資料", kind: .slides, slides: [slide])
      let preview = try CompanyPresentationPreview.make(document: document, template: source)
      precondition(preview.pages.count == 1 && preview.originalPageCount == 1 && preview.pages[0].sourceID == slide.id)
      let elements = preview.pages[0].elements!
      precondition(elements[0].fill == "005A50" && elements[0].x == 800 && elements[0].y == 2)
      precondition(elements[1].fill == "002D28" && elements[1].x == 680 && elements[2].fill == "ABFFF6" && elements[2].x == 560)
      precondition(!elements.contains { $0.fill == PresentationTheme.blue || $0.fill == PresentationTheme.orange })
      precondition(elements.filter { $0.kind == .text }.allSatisfy { $0.fontName == "Hiragino Sans" && $0.latinFontName == "Helvetica Neue" })
      let repeated = try CompanyPresentationPreview.make(document: document, template: source)
      precondition(preview.pages == repeated.pages)
      let pdf = try CompanyPresentationPDF.data(for: preview)
      guard let parsed = PDFDocument(data: pdf), parsed.pageCount == 1, let text = parsed.string else { preconditionFailure("PDF missing") }
      precondition(text.contains("判断") && !text.contains("含めない原本ページ"))
      precondition((parsed.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.contains("原本ページは含みません") == true)
      try pdf.write(to: output.appendingPathComponent(id + ".pdf"))
      try render(pdf, to: images.appendingPathComponent(id + ".png"))
      let pptx = try CompanyPresentationExporter.data(for: document, template: source)
      try pptx.write(to: output.appendingPathComponent(id + ".pptx"))
      print("PASS corporate preview \(id): selected layout, company colors/fonts, master/layout luminance decorations, PDF Japanese/pixels, original excluded, deterministic scene")
    }
    let deck = MemoraDocument(title: "会社書式の65型", kind: .slides, slides: slides)
    let aggregate = try CompanyPresentationPreview.make(document: deck, template: source)
    let pdf = try CompanyPresentationPDF.data(for: aggregate)
    precondition(PDFDocument(data: pdf)?.pageCount == 65)
    try pdf.write(to: output.appendingPathComponent("corporate-additions-65.pdf"))
    try CompanyPresentationExporter.data(for: deck, template: source).write(to: output.appendingPathComponent("corporate-catalog.pptx"))
    let greenTint = try CompanyPresentationColor.tint("005A50", multiplier: 0.2, offset: 0.8)
    let blackTint = try CompanyPresentationColor.tint("000000", multiplier: 0.2, offset: 0.8)
    precondition(greenTint == "ABFFF6" && blackTint == "CCCCCC")
    for variant in [
      decoration.replacingOccurrences(of: "<a:ln><a:noFill/></a:ln>", with: ""),
      decoration.replacingOccurrences(of: "<a:schemeClr val='accent1'/>", with: "<a:schemeClr val='accent1'><a:alpha val='50000'/></a:schemeClr>"),
      decoration.replacingOccurrences(of: "prst='rect'", with: "prst='diamond'"),
      decoration.replacingOccurrences(of: "<p:sp>", with: "<p:sp useBgFill='1'>"),
      decoration.replacingOccurrences(of: "</p:sp>", with: "<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>会社の文字</a:t></a:r></a:p></p:txBody></p:sp>"),
      decoration.replacingOccurrences(of: "name='Fictional mark'", with: "name='Fictional mark' hidden='1'"),
      decoration.replacingOccurrences(of: "</p:spPr>", with: "<a:solidFill><a:srgbClr val='FF0000'/></a:solidFill></p:spPr>")
    ] {
      let unsupported = try changing(source) { _, text in text.replacingOccurrences(of: decoration, with: variant) }
      do { _ = try CompanyPresentationPreview.make(document: deck, template: unsupported); preconditionFailure("Company artwork silently lost") } catch {}
    }
    print("Corporate preview: 65/65 native scenes and real PDF pages; unsupported artwork rejected; original pages excluded, no Office/device certification")
  }

  static func changing(_ bytes: Data, change: (String, String) -> String) throws -> Data {
    var input = try OfficeArchiveReader(data: bytes), output = ZipArchive()
    for path in input.partNames { output.add(path, text: change(path, String(decoding: try input.read(path), as: UTF8.self))) }
    return output.data()
  }

  static func render(_ data: Data, to url: URL) throws {
    let pdf = CGPDFDocument(CGDataProvider(data: data as CFData)!)!
    let context = CGContext(data: nil, width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: 3840,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 960, height: 540))
    context.drawPDFPage(pdf.page(at: 1)!)
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    for (x, expected) in [(850, [0,90,80]), (730, [0,45,40]), (610, [171,255,246])] {
      let offset = 10 * 3840 + x * 4
      precondition((0..<3).allSatisfy { Int(pixels[offset + $0]) == expected[$0] }, "Company HSL/sRGB changed in actual PDF rendering")
    }
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
  }
}
