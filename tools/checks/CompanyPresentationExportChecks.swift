import Foundation

@main enum CompanyPresentationExportChecks {
  static func require(_ value: @autoclosure () throws -> Bool) throws {
    if try !value() { preconditionFailure("Company export assertion failed") }
  }
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let base = PPTXWriter.data(for: .init(title: "会社の原本", kind: .slides, slides: [.init(title: "原本を保持", bullets: ["日本語の元データ"]) ]))
    let logo = "<p:sp><p:nvSpPr><p:cNvPr id='40' name='Corporate fixture'/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x='10160000' y='25400'/><a:ext cx='1270000' cy='203200'/></a:xfrm><a:prstGeom prst='rect'><a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val='accent1'/></a:solidFill></p:spPr></p:sp>"
    let source = try changing(base) { path, value in
      if path == "ppt/slideMasters/slideMaster1.xml" { return value.replacingOccurrences(of: "</p:spTree>", with: logo + "</p:spTree>") }
      if path == "ppt/theme/theme1.xml" { return value.replacingOccurrences(of: "<a:accent1><a:srgbClr val=\"0D0D0D\"/></a:accent1>", with: "<a:accent1><a:srgbClr val=\"005A50\"/></a:accent1>")
        .replacingOccurrences(of: "<a:accent2><a:srgbClr val=\"303030\"/></a:accent2>", with: "<a:accent2><a:srgbClr val=\"803300\"/></a:accent2>") }
      return value
    }
    try source.write(to: root.appendingPathComponent("source.pptx"))
    try require(CompanyPresentationExporter.canAppend(CompanyTemplateEngine.analyze(source, format: .pptx)))
    let scalarSource = try changing(source) { path, value in path == "ppt/slides/slide1.xml" ? value.replacingOccurrences(of: "原本を保持", with: "{{title}}") : value }
    let scalarAnalysis = try CompanyTemplateEngine.analyze(scalarSource, format: .pptx)
    try require(scalarAnalysis.isAvailable && !CompanyPresentationExporter.canAppend(scalarAnalysis))
    let slides = SlideArchetype.allCases.map { PresentationExample.slide($0) }
    for slide in slides {
      let document = MemoraDocument(title: "架空の会社資料", kind: .slides, slides: [slide])
      let result = try CompanyPresentationExporter.data(for: document, template: source)
      try result.write(to: root.appendingPathComponent("\(slide.composition!.layout.rawValue).pptx"))
      var before = try OfficeArchiveReader(data: source), after = try OfficeArchiveReader(data: result)
      for path in before.partNames where !["ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "[Content_Types].xml"].contains(path) {
        try require(try before.read(path) == after.read(path))
      }
      let xml = String(decoding: try after.read("ppt/slides/slide2.xml"), as: UTF8.self)
      try require(xml.contains("<p:sp>") && xml.contains("<a:schemeClr") && !xml.contains("<p:bg>"))
      try require(!xml.contains("2563EB") && !xml.contains("F28C28"))
      let notes = String(decoding: try after.read("ppt/notesSlides/notesSlide1.xml"), as: UTF8.self)
      try require(notes.contains("<p:notes") && notes.contains("<a:t") && notes.contains("+mn-ea"))
      if [.b13, .m14].contains(slide.composition!.layout) {
        try require(xml.contains("<a:lumMod val=\"20000\"/><a:lumOff val=\"80000\"/>"))
      }
      let second = try CompanyPresentationExporter.data(for: document, template: source)
      try require(second == result)
      var analyzer = try CompanyPresentationAnalyzer(data: result)
      try require(try analyzer.measure().slideCount == 2)
      print("PASS corporate \(slide.composition!.layout.rawValue): editable shapes, theme links, notes, unchanged original parts, deterministic package")
    }
    let deck = MemoraDocument(title: "会社書式の65型", kind: .slides, slides: slides)
    let aggregate = try CompanyPresentationExporter.data(for: deck, template: source)
    try aggregate.write(to: root.appendingPathComponent("corporate-catalog.pptx"))
    var analyzer = try CompanyPresentationAnalyzer(data: aggregate)
    try require(try analyzer.measure().slideCount == 66)
    let existingNotes = PPTXWriter.data(for: .init(title: "既存ノート", kind: .slides, slides: [.init(title: "保持", bullets: ["元の内容"], notes: "元のノート")]))
    let withNotes = try CompanyPresentationExporter.data(for: .init(title: "追加", kind: .slides, slides: [slides[0]]), template: existingNotes)
    let noteArchive = try OfficeArchiveReader(data: withNotes)
    try require(noteArchive.partNames.filter { $0.hasPrefix("ppt/notesMasters/") && $0.hasSuffix(".xml") }.count == 1)
    let sample = MemoraDocument(title: "検査", kind: .slides, slides: [slides[0]])
    let properties = "<Properties xmlns='http://schemas.openxmlformats.org/officeDocument/2006/extended-properties'><Slides>1</Slides><!--retain metadata--></Properties>"
    var sourceArchive = try OfficeArchiveReader(data: source), propertySource = ZipArchive()
    for path in sourceArchive.partNames { propertySource.add(path, data: try sourceArchive.read(path)) }
    propertySource.add("docProps/app.xml", text: properties)
    var withProperties = try OfficeArchiveReader(data: CompanyPresentationExporter.data(for: sample, template: propertySource.data()))
    try require(String(decoding: try withProperties.read("docProps/app.xml"), as: UTF8.self) == properties.replacingOccurrences(of: "<Slides>1</Slides>", with: "<Slides>2</Slides>"))
    let orphanPath = "ppt/slides/_rels/slide2.xml.rels"
    let orphan = Data("<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><!--retain orphan--></Relationships>".utf8)
    propertySource.add(orphanPath, data: orphan)
    var withOrphan = try OfficeArchiveReader(data: CompanyPresentationExporter.data(for: sample, template: propertySource.data()))
    try require(try withOrphan.read(orphanPath) == orphan)
    try require(withOrphan.partNames.contains("ppt/slides/slide3.xml"))
    for invalid in [
      try changing(source) { path, value in path == "ppt/presentation.xml" ? value.replacingOccurrences(of: "cx=\"12192000\"", with: "cx=\"9144000\"") : value },
      try changing(source) { path, value in path == "ppt/theme/theme1.xml" ? value.replacingOccurrences(of: "Hiragino Sans", with: "MemoraMissingFontFixture_91") : value },
      try changing(source) { path, value in path == "ppt/slideMasters/slideMaster1.xml" ? value.replacingOccurrences(of: "x='10160000' y='25400'", with: "x='1016000' y='2540000'").replacingOccurrences(of: "cx='1270000' cy='203200'", with: "cx='10000000' cy='2032000'") : value },
      try changing(source) { path, value in path == "ppt/theme/theme1.xml" ? value.replacingOccurrences(of: "005A50", with: "FFFFFF") : value },
      try changing(source) { path, value in path == "ppt/theme/theme1.xml" ? value.replacingOccurrences(of: "<a:srgbClr val=\"005A50\"/>", with: "<a:srgbClr val=\"005A50\"><a:lumOff val='80000'/></a:srgbClr>") : value },
      try changing(source) { path, value in path == "ppt/slides/slide1.xml" ? value.replacingOccurrences(of: "原本を保持", with: "{{title}}") : value },
      try changing(source) { path, value in path == "ppt/slides/slide1.xml" ? value.replacingOccurrences(of: "原本を保持", with: "{{unfinished") : value },
      try changing(source) { path, value in path == "[Content_Types].xml" ? value.replacingOccurrences(of: "</Types>", with: "<Override PartName='/missing.xml' ContentType='application/xml'/></Types>") : value }
    ] {
      do { _ = try CompanyPresentationExporter.data(for: sample, template: invalid); preconditionFailure("incompatible template accepted") } catch {}
    }
    do { _ = try CompanyPresentationExporter.data(for: .init(title: "従来の本文", kind: .slides, slides: [.init(title: "従来", bullets: ["箇条書き"])]), template: source); preconditionFailure("legacy was silently replaced") } catch {}
    let bytes = Data("<?xml version='1.0'?><root><slot a='x&gt;y'/><!--retain--><ext><![CDATA[a < b]]></ext></root>".utf8)
    let patch = try OfficeXMLInsertion(bytes)
    let inserted = String(decoding: try patch.inserting("<child/>", into: 1), as: UTF8.self)
    try require(inserted.contains("<slot a='x&gt;y'><child/></slot><!--retain--><ext><![CDATA[a < b]]></ext>"))
    print("Corporate export: 65/65 host checks; existing notes reuse, slide-count metadata, theme tint, incompatible geometry/font/contrast/collision/markers/parts/legacy rejection and verbatim XML insertion passed. Office/Keynote/device rendering NOT certified.")
  }

  static func changing(_ data: Data, change: (String, String) -> String) throws -> Data {
    var source = try OfficeArchiveReader(data: data), result = ZipArchive()
    for path in source.partNames { result.add(path, text: change(path, String(decoding: try source.read(path), as: UTF8.self))) }
    return result.data()
  }
}
