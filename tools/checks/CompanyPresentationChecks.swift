import Foundation

enum CompanyPresentationChecks {
  static func require(_ condition: @autoclosure () throws -> Bool) throws {
    let satisfied = try condition()
    if !satisfied { preconditionFailure("Company presentation assertion failed") }
  }

  static func run(root: URL) throws {
    let source = PPTXWriter.data(for: .init(title: "架空テンプレート", kind: .slides,
      slides: [.init(title: "{{title}}", bullets: ["{{body}}"], notes: "原本ノート")]))
    let master = "ppt/slideMasters/slideMaster1.xml", layout = "ppt/slideLayouts/slideLayout1.xml"
    func placeholder(_ kind: String, index: Int, frame: Bool, size: Int = 2400) -> String {
      let position = frame ? "<a:xfrm><a:off x='635000' y='508000'/><a:ext cx='10033000' cy='1016000'/></a:xfrm>" : ""
      return "<p:sp><p:nvSpPr><p:cNvPr id='\(index + 20)' name='架空欄'/><p:cNvSpPr/><p:nvPr><p:ph type='\(kind)' idx='\(index)'/></p:nvPr></p:nvSpPr><p:spPr>\(position)</p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz='\(size)'><a:ea typeface='検証フォント'/></a:defRPr></a:pPr><a:endParaRPr/></a:p></p:txBody></p:sp>"
    }
    let picture = "<p:pic><p:nvPicPr><p:cNvPr id='90' name='架空画像'/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:spPr><a:xfrm><a:off x='100' y='200'/><a:ext cx='300' cy='400'/></a:xfrm></p:spPr></p:pic>"
    let fixture = try replace(source, parts: [
      master: { $0.replacingOccurrences(of: "</p:spTree>", with: placeholder("title", index: 0, frame: true) + placeholder("body", index: 1, frame: true, size: 1800) + picture + "</p:spTree>") },
      layout: { $0.replacingOccurrences(of: "<p:cSld name=\"Blank\">", with: "<p:cSld name='架空の本文書式'>")
        .replacingOccurrences(of: "</p:spTree>", with: placeholder("title", index: 0, frame: false) + placeholder("body", index: 1, frame: false) + "</p:spTree>") }
    ])
    let analysis = try CompanyTemplateEngine.analyze(fixture, format: .pptx)
    let profile = analysis.presentation!
    try require(profile.widthEMU == PPTXWriter.slideWidth && profile.heightEMU == PPTXWriter.slideHeight && profile.slideCount == 1)
    try require(profile.masters.count == 1 && profile.layouts.count == 1 && profile.layouts[0].useCount == 1)
    try require(profile.layouts[0].name == "架空の本文書式" && profile.layouts[0].masterPart == master)
    try require(profile.layouts[0].placeholders.map(\.id) == ["title:0", "body:1"])
    try require(profile.layouts[0].placeholders.allSatisfy { $0.frameSource == master && $0.frame?.x == 635000 && $0.font == "検証フォント" })
    try require(profile.layouts[0].placeholders[1].fontSize == 24) // Layout overrides the master's 18pt.
    try require(profile.masters[0].placeholders[1].fontSize == 18)
    try require(profile.masters[0].decorations.count == 1 && profile.masters[0].decorations[0].kind == "pic")
    try require(profile.masters[0].theme?.colors["dk1"] == "0D0D0D" && profile.masters[0].theme?.bodyFonts["Jpan"] == "Hiragino Sans")
    try require(profile.layouts[0].background == "srgbClr: FFFFFF")
    try require(try JSONDecoder().decode(CompanyTemplateEngine.Analysis.self, from: JSONEncoder().encode(analysis)) == analysis)
    let legacy = Data(#"{"placeholders":["title"],"features":[],"unsupportedSplitMarkers":false,"engineVersion":2}"#.utf8)
    try require(try JSONDecoder().decode(CompanyTemplateEngine.Analysis.self, from: legacy).presentation == nil)
    let file = root.appendingPathComponent("measured-template.pptx")
    try fixture.write(to: file)
    try require(try CompanyTemplateEngine.analyze(file, format: .pptx) == analysis)
    let filled = try CompanyTemplateEngine.fill(file, format: .pptx, values: ["title": "日本語の報告", "body": "根拠を保持"])
    try require(try Data(contentsOf: file) == fixture)
    var before = try OfficeArchiveReader(data: fixture), after = try OfficeArchiveReader(data: filled)
    for part in before.partNames where part != "ppt/slides/slide1.xml" {
      try require(try before.read(part) == after.read(part))
    }
    try require(try CompanyTemplateEngine.analyze(filled, format: .pptx).presentation == profile)
    try JSONEncoder().encode(profile).write(to: root.appendingPathComponent("company-profile.json"))
    try filled.write(to: root.appendingPathComponent("measured-filled.pptx"))

    let customPrefix = try replace(fixture, parts: [master: { $0.replacingOccurrences(of: "xmlns:p=", with: "xmlns:present=").replacingOccurrences(of: "<p:", with: "<present:").replacingOccurrences(of: "</p:", with: "</present:") }])
    try require(try CompanyTemplateEngine.analyze(customPrefix, format: .pptx).presentation == profile)
    let strict = try replaceAll(fixture) { $0
      .replacingOccurrences(of: "http://schemas.openxmlformats.org/presentationml/2006/main", with: "http://purl.oclc.org/ooxml/presentationml/main")
      .replacingOccurrences(of: "http://schemas.openxmlformats.org/drawingml/2006/main", with: "http://purl.oclc.org/ooxml/drawingml/main")
      .replacingOccurrences(of: "http://schemas.openxmlformats.org/officeDocument/2006/relationships", with: "http://purl.oclc.org/ooxml/officeDocument/relationships") }
    try require(try CompanyTemplateEngine.analyze(strict, format: .pptx).presentation == profile)
    let foreignColor = try replace(fixture, parts: ["ppt/theme/theme1.xml": { $0.replacingOccurrences(of: "<a:dk1><a:srgbClr val=\"0D0D0D\"/></a:dk1>", with: "<a:dk1><other:srgbClr xmlns:other='urn:unrelated' val='FF0000'/></a:dk1>") }])
    try require(try CompanyTemplateEngine.analyze(foreignColor, format: .pptx).presentation!.masters[0].theme?.colors["dk1"] == nil)
    let incomplete = try replace(fixture, parts: [layout: { $0.replacingOccurrences(of: "idx='1'", with: "idx='9'") }])
    let missing = try CompanyTemplateEngine.analyze(incomplete, format: .pptx).presentation!.layouts[0]
    try require(missing.placeholders[1].frame == nil && !missing.notices.isEmpty) // Never guess the wrong body slot.
    let grouped = try replace(fixture, parts: [master: { $0.replacingOccurrences(of: "</p:spTree>", with: "<p:grpSp/>" + "</p:spTree>") }])
    try require(try CompanyTemplateEngine.analyze(grouped, format: .pptx).presentation!.layouts[0].notices.contains { $0.contains("グループ") })
    let gradient = try replace(fixture, parts: [master: { $0.replacingOccurrences(of: "<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>", with: "<a:gradFill><a:gsLst><a:gs pos='0'><a:srgbClr val='FF0000'/></a:gs><a:gs pos='100000'><a:srgbClr val='FFFFFF'/></a:gs></a:gsLst></a:gradFill>") }])
    try require(try CompanyTemplateEngine.analyze(gradient, format: .pptx).presentation!.layouts[0].background == "画像・グラデーション等（再現未検証）")
    let rels = "ppt/slideLayouts/_rels/slideLayout1.xml.rels"
    for bad in [
      try replace(fixture, parts: [rels: { $0.replacingOccurrences(of: "../slideMasters/slideMaster1.xml", with: "../../../../escape.xml") }]),
      try replace(fixture, parts: [rels: { $0.replacingOccurrences(of: "../slideMasters/slideMaster1.xml", with: "https://example.invalid/company.pptx") }]),
      try replace(fixture, parts: [rels: { $0.replacingOccurrences(of: "../slideMasters/slideMaster1.xml", with: "../slideMasters/missing.xml") }]),
      try replace(fixture, parts: [layout: { $0.replacingOccurrences(of: "</p:spTree>", with: placeholder("title", index: 0, frame: false) + "</p:spTree>") }]),
      try replace(fixture, parts: ["ppt/presentation.xml": { $0.replacingOccurrences(of: "cx=\"12192000\"", with: "cx=\"-1\"") }])
    ] {
      do { _ = try CompanyTemplateEngine.analyze(bad, format: .pptx); preconditionFailure("malformed template accepted") } catch {}
    }
    print("CompanyPresentationChecks: passed (relationship-linked masters/layouts, exact EMU, per-layout usage, theme/Japanese fonts/colors, inherited frames, explicit font sizes, decorations/background, Strict/custom prefix, ambiguous body unresolved, groups disclosed, malformed/traversal/external/missing/duplicate references rejected, legacy decode, bounded file API, unchanged original/non-slide bytes; new-master application and Office rendering NOT validated)")
  }

  static func replace(_ data: Data, parts: [String: (String) -> String]) throws -> Data {
    var archive = try OfficeArchiveReader(data: data), output = ZipArchive()
    for name in archive.partNames {
      let bytes = try archive.read(name)
      if let change = parts[name] { output.add(name, text: change(String(decoding: bytes, as: UTF8.self))) }
      else { output.add(name, data: bytes) }
    }
    return output.data()
  }

  static func replaceAll(_ data: Data, change: (String) -> String) throws -> Data {
    var archive = try OfficeArchiveReader(data: data), output = ZipArchive()
    for name in archive.partNames { output.add(name, text: change(String(decoding: try archive.read(name), as: UTF8.self))) }
    return output.data()
  }
}
