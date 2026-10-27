import CoreText
import Foundation

/// Appends editable pages to a copy; existing masters, layouts and slides keep their bytes.
enum CompanyPresentationExporter {
  struct Failure: LocalizedError {
    var reason: String
    var errorDescription: String? { "会社書式へ追加できません。" + reason + "原本は変更していません。" }
  }
  private static let p = "http://schemas.openxmlformats.org/presentationml/2006/main"
  private static let a = "http://schemas.openxmlformats.org/drawingml/2006/main"
  private static let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  private static let package = "http://schemas.openxmlformats.org/package/2006/relationships"
  private static let types = "http://schemas.openxmlformats.org/package/2006/content-types"
  private static let namespaces = "xmlns:p=\"\(p)\" xmlns:a=\"\(a)\" xmlns:r=\"\(r)\""
  private static let palette = [PresentationTheme.white: "bg1", PresentationTheme.ink: "tx1", PresentationTheme.blue: "accent1",
    PresentationTheme.orange: "accent2", PresentationTheme.secondary: "tx2", PresentationTheme.pale: "bg2",
    PresentationTheme.rule: "tx2", "A3A3A3": "accent4", "DBEAFE": "accent1"]

  /// Stored metadata is only a hint. The actual file is remeasured at export.
  static func canAppend(_ analysis: CompanyTemplateEngine.Analysis) -> Bool {
    analysis.placeholders.isEmpty && !analysis.unsupportedSplitMarkers && hasCandidate(analysis.presentation)
  }

  static func hasCandidate(_ profile: CompanyPresentationProfile?) -> Bool {
    guard let profile, profile.isValid, profile.widthEMU == PPTXWriter.slideWidth, profile.heightEMU == PPTXWriter.slideHeight else { return false }
    return profile.layouts.contains { layout in
      layout.placeholders.isEmpty && ["blank", "未指定"].contains(layout.kind) && layout.notices.isEmpty &&
        profile.masters.contains { $0.id == layout.masterPart && $0.theme != nil && $0.placeholders.isEmpty }
    }
  }

  static func data(for document: MemoraDocument, template: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: template); defer { try? handle.close() }
    let bytes = try handle.read(upToCount: OfficeArchiveReader.maximumArchiveBytes + 1) ?? Data()
    return try data(for: document, template: bytes)
  }

  static func data(for document: MemoraDocument, template: Data) throws -> Data {
    try Task.checkCancellation()
    guard document.kind == .slides, (1...65).contains(document.slides.count), document.slides.allSatisfy({ $0.composition != nil }) else {
      throw Failure(reason: "1〜65枚の構造化スライドを指定してください。")
    }
    try PresentationExportCheck.validate(document)
    let analysis = try CompanyTemplateEngine.analyze(template, format: .pptx)
    guard let profile = analysis.presentation, hasCandidate(profile), profile.presentationPart == "ppt/presentation.xml",
          profile.slideCount > 0, profile.slideCount + document.slides.count <= 500,
          analysis.placeholders.isEmpty, !analysis.unsupportedSplitMarkers else {
      throw Failure(reason: "960×540pt・差し込み欄のない空白レイアウトが必要です。既存の差し込み方式は別に利用できます。")
    }
    var original = try OfficeArchiveReader(data: template), parts: [String: Data] = [:]
    for path in original.partNames where !path.hasSuffix("/") { parts[path] = try original.read(path) }
    for (path, data) in parts where path.hasSuffix(".rels") {
      let links = try OfficeXMLDocument(data: data)
      guard !links.nodes.contains(where: { $0.attributes["Type"] == r + "/themeOverride" }) else {
        throw Failure(reason: "個別テーマ上書きを持つ会社書式には未対応です。")
      }
    }
    func xml(_ path: String, root: String, namespace: String) throws -> OfficeXMLDocument {
      guard let data = parts[path] else { throw OfficeArchiveReader.Failure.invalid }
      let value = try OfficeXMLDocument(data: data)
      guard value.matches(0, root, namespaces: [namespace]) else { throw Failure(reason: "このXML形式には未対応です。") }
      return value
    }
    let mainPath = "ppt/presentation.xml", relPath = "ppt/_rels/presentation.xml.rels"
    let main = try xml(mainPath, root: "presentation", namespace: p)
    let rels = try xml(relPath, root: "Relationships", namespace: package)
    let contentTypes = try xml("[Content_Types].xml", root: "Types", namespace: types)
    let declared = contentTypes.children(0, named: "Override", namespaces: [types]).compactMap { contentTypes.nodes[$0].attributes["PartName"] }
    guard Set(declared.map { $0.lowercased() }).count == declared.count,
          declared.allSatisfy({ $0.hasPrefix("/") && parts[String($0.dropFirst())] != nil }) else { throw OfficeArchiveReader.Failure.invalid }
    let sourceSlides = main.nodes.filter { $0.name == "sldId" && $0.namespace == p }.compactMap { $0.attributes["id"].flatMap(Int.init) }
    guard sourceSlides.count == profile.slideCount, Set(sourceSlides).count == sourceSlides.count,
          sourceSlides.allSatisfy({ (256...2_147_483_647).contains($0) }),
          let lastSlideID = sourceSlides.max(), lastSlideID <= 2_147_483_647 - document.slides.count else { throw OfficeArchiveReader.Failure.invalid }
    var ids = Set(rels.nodes.compactMap { $0.attributes["Id"] }), paths = Set(parts.keys.map { $0.lowercased() })
    func newPath(_ directory: String, prefix: String) -> String {
      var number = 1
      while paths.contains("\(directory)/\(prefix)\(number).xml".lowercased()) ||
        paths.contains(relationshipPath("\(directory)/\(prefix)\(number).xml").lowercased()) { number += 1 }
      let path = "\(directory)/\(prefix)\(number).xml"
      paths.insert(path.lowercased()); paths.insert(relationshipPath(path).lowercased())
      return path
    }
    func newID() -> String {
      var number = 1
      while ids.contains("rIdMemora\(number)") { number += 1 }
      let id = "rIdMemora\(number)"; ids.insert(id); return id
    }
    let selection = try choose(profile: profile, document: document)
    _ = try xml(selection.layout.id, root: "sldLayout", namespace: p)
    _ = try xml(selection.master.id, root: "sldMaster", namespace: p)
    _ = try xml(selection.master.theme!.part, root: "theme", namespace: a)
    var overrides = "", relationships = "", slideIDs = ""
    func override(_ path: String, _ type: String) -> String {
      "<Override xmlns=\"\(types)\" PartName=\"/\(path)\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.\(type)+xml\"/>"
    }
    let noteMaster: String
    let notesLinks = rels.nodes.filter { $0.namespace == package && $0.name == "Relationship" && $0.attributes["Type"] == r + "/notesMaster" }
    if let existing = notesLinks.first {
      guard notesLinks.count == 1, let target = existing.attributes["Target"], target.range(of: #"^notesMasters/[A-Za-z0-9_.-]+\.xml$"#, options: .regularExpression) != nil,
            parts["ppt/" + target] != nil else { throw Failure(reason: "ノートマスターの参照方式には未対応です。") }
      noteMaster = "ppt/" + target
      guard let list = main.children(0, named: "notesMasterIdLst", namespaces: [p]).first,
            main.children(0, named: "notesMasterIdLst", namespaces: [p]).count == 1,
            main.children(list, named: "notesMasterId", namespaces: [p]).count == 1,
            main.nodes[main.children(list, named: "notesMasterId", namespaces: [p])[0]].relationshipID == existing.attributes["Id"] else { throw OfficeArchiveReader.Failure.invalid }
    } else {
      guard main.children(0, named: "notesMasterIdLst", namespaces: [p]).isEmpty else { throw OfficeArchiveReader.Failure.invalid }
      noteMaster = newPath("ppt/notesMasters", prefix: "notesMaster")
      parts[noteMaster] = Data(PPTXWriter.notesMaster.utf8)
      parts[relationshipPath(noteMaster)] = Data(relsXML([("rIdTheme", "theme", "../theme/" + (selection.master.theme!.part as NSString).lastPathComponent)]).utf8)
      overrides += override(noteMaster, "notesMaster")
      let id = newID()
      relationships += relation(id, type: "notesMaster", target: String(noteMaster.dropFirst(4)))
      let patch = try OfficeXMLInsertion(parts[mainPath]!)
      guard let slideList = patch.document.children(0, named: "sldIdLst", namespaces: [p]).first else { throw OfficeArchiveReader.Failure.invalid }
      parts[mainPath] = try patch.inserting("<p:notesMasterIdLst xmlns:p=\"\(p)\" xmlns:r=\"\(r)\"><p:notesMasterId r:id=\"\(id)\"/></p:notesMasterIdLst>", before: slideList)
    }
    for (index, slide) in document.slides.enumerated() {
      try Task.checkCancellation()
      let slidePath = newPath("ppt/slides", prefix: "slide"), notePath = newPath("ppt/notesSlides", prefix: "notesSlide")
      let elements = try themedElements(slide, theme: selection.master.theme!)
      let shapes = PresentationOOXML.shapes(elements, schemeColors: palette, lightenedColors: [PresentationTheme.rule, "DBEAFE"])
      parts[slidePath] = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sld \(namespaces)><p:cSld><p:spTree>\(PPTXWriter.emptyTree)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>").utf8)
      parts[relationshipPath(slidePath)] = Data(relsXML([("rIdLayout", "slideLayout", "../slideLayouts/" + (selection.layout.id as NSString).lastPathComponent),
        ("rIdNotes", "notesSlide", "../notesSlides/" + (notePath as NSString).lastPathComponent)]).utf8)
      let notes = ([slide.notes] + slide.composition!.readingText).filter { !$0.isEmpty }.joined(separator: "\n\n")
      parts[notePath] = Data(PPTXWriter.notesXML(notes)
        .replacingOccurrences(of: "typeface=\"Helvetica Neue\"", with: "typeface=\"+mn-lt\"")
        .replacingOccurrences(of: "typeface=\"Hiragino Sans\"", with: "typeface=\"+mn-ea\"").utf8)
      parts[relationshipPath(notePath)] = Data(relsXML([("rIdMaster", "notesMaster", "../notesMasters/" + (noteMaster as NSString).lastPathComponent),
        ("rIdSlide", "slide", "../slides/" + (slidePath as NSString).lastPathComponent)]).utf8)
      overrides += override(slidePath, "slide") + override(notePath, "notesSlide")
      let id = newID()
      relationships += relation(id, type: "slide", target: String(slidePath.dropFirst(4)))
      slideIDs += "<p:sldId xmlns:p=\"\(p)\" xmlns:r=\"\(r)\" id=\"\(lastSlideID + index + 1)\" r:id=\"\(id)\"/>"
    }
    let patch = try OfficeXMLInsertion(parts[mainPath]!)
    guard let list = patch.document.children(0, named: "sldIdLst", namespaces: [p]).first else { throw OfficeArchiveReader.Failure.invalid }
    parts[mainPath] = try patch.inserting(slideIDs, into: list)
    parts[relPath] = try OfficeXMLInsertion(parts[relPath]!).inserting(relationships, into: 0)
    parts["[Content_Types].xml"] = try OfficeXMLInsertion(parts["[Content_Types].xml"]!).inserting(overrides, into: 0)
    if let appProperties = parts["docProps/app.xml"] {
      let patch = try OfficeXMLInsertion(appProperties)
      let namespace = "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
      guard patch.document.matches(0, "Properties", namespaces: [namespace]) else { throw Failure(reason: "資料プロパティの形式には未対応です。") }
      let counts = patch.document.children(0, named: "Slides", namespaces: [namespace])
      guard counts.count <= 1 else { throw OfficeArchiveReader.Failure.invalid }
      if let index = counts.first { parts["docProps/app.xml"] = try patch.replacingLeafText(String(profile.slideCount + document.slides.count), at: index) }
    }
    guard parts.count <= 2048, parts.values.reduce(0, { $0 + $1.count }) <= OfficeArchiveReader.maximumReadBytes else { throw OfficeArchiveReader.Failure.limit }
    var output = ZipArchive()
    for path in parts.keys.sorted() { output.add(path, data: parts[path]!) }
    let result = output.data()
    var check = try CompanyPresentationAnalyzer(data: result)
    guard try check.measure().slideCount == profile.slideCount + document.slides.count else { throw OfficeArchiveReader.Failure.invalid }
    return result
  }

  private static func choose(profile: CompanyPresentationProfile, document: MemoraDocument) throws -> (layout: CompanyPresentationProfile.Layout, master: CompanyPresentationProfile.Master) {
    var lastFailure: Error?
    for layout in profile.layouts where layout.placeholders.isEmpty && layout.notices.isEmpty && ["blank", "未指定"].contains(layout.kind) {
      guard layout.id.range(of: #"^ppt/slideLayouts/[A-Za-z0-9_.-]+\.xml$"#, options: .regularExpression) != nil,
            let master = profile.masters.first(where: { $0.id == layout.masterPart }), master.placeholders.isEmpty, let theme = master.theme,
            theme.part.range(of: #"^ppt/theme/[A-Za-z0-9_.-]+\.xml$"#, options: .regularExpression) != nil,
            layout.background == nil || layout.background == "srgbClr: FFFFFF" || layout.background == "schemeClr: bg1" else { continue }
      let decorations = layout.decorations + master.decorations
      guard decorations.allSatisfy({ $0.frame != nil }) else { continue }
      do {
        try validateTheme(master)
        var safe = true
        for slide in document.slides {
          let elements = try themedElements(slide, theme: theme)
          for decoration in decorations {
            let f = decoration.frame!
            for e in elements where min(e.maxX, Double(f.x + f.width) / 12700) - max(e.x, Double(f.x) / 12700) > 0 &&
              min(e.maxY, Double(f.y + f.height) / 12700) - max(e.y, Double(f.y) / 12700) > 0 { safe = false }
          }
        }
        if safe { return (layout, master) }
      } catch is CancellationError { throw CancellationError() }
      catch { lastFailure = error }
    }
    if let lastFailure { throw lastFailure }
    throw Failure(reason: "装飾・フォント・背景と両立する空白レイアウトがありません。")
  }

  private static func validateTheme(_ master: CompanyPresentationProfile.Master) throws {
    let defaults = ["bg1": "lt1", "bg2": "lt2", "tx1": "dk1", "tx2": "dk2"]
    var colors: [String: Double] = [:]
    for role in Set(palette.values) {
      let slot = master.colorMap[role] ?? defaults[role] ?? role
      guard let hex = master.theme?.colors[slot], let value = UInt32(hex, radix: 16) else { throw Failure(reason: "テーマ色を確定できません。") }
      let rgb = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { v -> Double in
        let s = v / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
      }
      colors[role] = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
    }
    for pair in [("tx1", "bg1", 4.5), ("tx1", "bg2", 4.5), ("bg1", "accent1", 4.5), ("bg1", "accent2", 4.5), ("tx2", "bg1", 3.0), ("accent4", "bg1", 3.0)] {
      let first = colors[pair.0]!, second = colors[pair.1]!
      guard (max(first, second) + 0.05) / (min(first, second) + 0.05) >= pair.2 else { throw Failure(reason: "この型で文字を読めるテーマ配色ではありません。") }
    }
    guard colors["bg1"]! > 0.99 else { throw Failure(reason: "この版は白い背景の会社書式が対象です。") }
  }

  private static func themedElements(_ slide: DocumentSlide, theme: CompanyPresentationProfile.Theme) throws -> [PresentationElement] {
    func face(_ fonts: [String: String], japanese: Bool) throws -> String {
      guard let name = japanese ? fonts["Jpan"] ?? fonts["ea"] ?? fonts["latin"] : fonts["latin"], !name.isEmpty else { throw Failure(reason: "テーマのフォントを確定できません。") }
      let font = PresentationText.font(size: 20, bold: false, name: name)
      let names = [CTFontCopyFamilyName(font) as String, CTFontCopyFullName(font) as String, CTFontCopyPostScriptName(font) as String]
      guard names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { throw Failure(reason: "指定フォント「\(name)」を端末で計測できません。") }
      return name
    }
    let heading = (try face(theme.headingFonts, japanese: true), try face(theme.headingFonts, japanese: false))
    let body = (try face(theme.bodyFonts, japanese: true), try face(theme.bodyFonts, japanese: false))
    return try PresentationLayoutEngine.elements(for: slide).map { original in
      var e = original
      guard palette[e.color] != nil, e.fill == nil || palette[e.fill!] != nil else { throw Failure(reason: "テーマへ対応できない色があります。") }
      e.fontName = e.bold ? heading.0 : body.0; e.latinFontName = e.bold ? heading.1 : body.1
      if e.kind == .text, Double(PresentationText.lines(e).count) * e.fontSize * 1.3 > e.height + 1 || PresentationText.widestLine(e) > e.width + 1 {
        throw Failure(reason: "会社フォントでは文字が枠に収まりません。内容を短くしてください。")
      }
      return e
    }
  }

  private static func relationshipPath(_ part: String) -> String { (part as NSString).deletingLastPathComponent + "/_rels/" + (part as NSString).lastPathComponent + ".rels" }
  private static func relation(_ id: String, type: String, target: String) -> String { "<Relationship xmlns=\"\(package)\" Id=\"\(id)\" Type=\"\(r)/\(type)\" Target=\"\(target)\"/>" }
  private static func relsXML(_ values: [(String, String, String)]) -> String { "<Relationships xmlns=\"\(package)\">" + values.map { relation($0.0, type: $0.1, target: $0.2) }.joined() + "</Relationships>" }
}
