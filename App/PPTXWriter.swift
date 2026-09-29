import Foundation

/// Writes slides as a PowerPoint (.pptx) file that Keynote, PowerPoint and
/// Google Slides open. Each slide is drawn with text boxes at fixed positions
/// that match `SlideView`, so the file looks like the app's preview.
enum PPTXWriter {
  /// 16:9 in EMU; one point is 12,700 EMU, so this is `SlideView`'s 960 × 540.
  static let slideWidth = 12_192_000
  static let slideHeight = 6_858_000
  static let accentHex = "0A84FF"
  static let textHex = "1C1C1E"
  static let secondaryHex = "6E6E73"

  static func data(for document: MemoraDocument) -> Data {
    var archive = ZipArchive()
    let slides = document.slides.isEmpty
      ? [DocumentSlide(title: document.displayTitle, bullets: [])]
      : document.slides

    archive.add("[Content_Types].xml", text: contentTypes(slideCount: slides.count))
    archive.add("_rels/.rels", text: rootRelationships)
    archive.add("ppt/presentation.xml", text: presentation(slideCount: slides.count))
    archive.add("ppt/_rels/presentation.xml.rels", text: presentationRelationships(slideCount: slides.count))
    archive.add("ppt/slideMasters/slideMaster1.xml", text: slideMaster)
    archive.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", text: slideMasterRelationships)
    archive.add("ppt/slideLayouts/slideLayout1.xml", text: slideLayout)
    archive.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", text: slideLayoutRelationships)
    archive.add("ppt/theme/theme1.xml", text: theme)
    for (index, slide) in slides.enumerated() {
      archive.add("ppt/slides/slide\(index + 1).xml", text: slideXML(slide))
      archive.add("ppt/slides/_rels/slide\(index + 1).xml.rels", text: slideRelationships)
    }
    return archive.data()
  }

  /// Writes the file to the temporary folder for the share sheet.
  static func write(_ document: MemoraDocument) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(document.exportFileName)-\(UUID().uuidString.prefix(8)).pptx")
    try data(for: document).write(to: url, options: .atomic)
    return url
  }

  // MARK: - Package parts

  private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
  private static let namespaces = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main""#
  private static let relationshipBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

  private static func contentTypes(slideCount: Int) -> String {
    let slides = (1...slideCount).map {
      #"<Override PartName="/ppt/slides/slide\#($0).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>"#
    }.joined()
    return header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>"# + slides + "</Types>"
  }

  private static var rootRelationships: String {
    header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/officeDocument" Target="ppt/presentation.xml"/></Relationships>"#
  }

  private static func presentation(slideCount: Int) -> String {
    let ids = (1...slideCount).map { #"<p:sldId id="\#(255 + $0)" r:id="rId\#($0 + 2)"/>"# }.joined()
    return header + #"<p:presentation \#(namespaces)><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>\#(ids)</p:sldIdLst><p:sldSz cx="\#(slideWidth)" cy="\#(slideHeight)"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#
  }

  private static func presentationRelationships(slideCount: Int) -> String {
    let slides = (1...slideCount).map {
      #"<Relationship Id="rId\#($0 + 2)" Type="\#(relationshipBase)/slide" Target="slides/slide\#($0).xml"/>"#
    }.joined()
    return header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/slideMaster" Target="slideMasters/slideMaster1.xml"/><Relationship Id="rId2" Type="\#(relationshipBase)/theme" Target="theme/theme1.xml"/>"# + slides + "</Relationships>"
  }

  private static let emptyTree = #"<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>"#

  private static var slideMaster: String {
    header + #"<p:sldMaster \#(namespaces)><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>\#(emptyTree)</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>"#
  }

  private static var slideMasterRelationships: String {
    header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="\#(relationshipBase)/theme" Target="../theme/theme1.xml"/></Relationships>"#
  }

  private static var slideLayout: String {
    header + #"<p:sldLayout \#(namespaces) preserve="1"><p:cSld name="Blank"><p:spTree>\#(emptyTree)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"#
  }

  private static var slideLayoutRelationships: String {
    header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>"#
  }

  private static var slideRelationships: String {
    header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>"#
  }

  private static var theme: String {
    let font = #"<a:latin typeface="Helvetica Neue"/><a:ea typeface=""/><a:cs typeface=""/><a:font script="Jpan" typeface="Hiragino Sans"/>"#
    let fill = #"<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>"#
    let colors = [
      ("dk1", textHex), ("lt1", "FFFFFF"), ("dk2", "3A3A3C"), ("lt2", "F2F2F7"),
      ("accent1", accentHex), ("accent2", "30B0C7"), ("accent3", "34C759"), ("accent4", "FF9F0A"),
      ("accent5", "AF52DE"), ("accent6", "FF375F"), ("hlink", accentHex), ("folHlink", "5E5CE6")
    ].map { #"<a:\#($0.0)><a:srgbClr val="\#($0.1)"/></a:\#($0.0)>"# }.joined()
    let lines = [6350, 12700, 19050].map { #"<a:ln w="\#($0)">\#(fill)</a:ln>"# }.joined()
    let effects = String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3)
    return header + #"<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Memora"><a:themeElements><a:clrScheme name="Memora">\#(colors)</a:clrScheme><a:fontScheme name="Memora"><a:majorFont>\#(font)</a:majorFont><a:minorFont>\#(font)</a:minorFont></a:fontScheme><a:fmtScheme name="Memora"><a:fillStyleLst>\#(fill)\#(fill)\#(fill)</a:fillStyleLst><a:lnStyleLst>\#(lines)</a:lnStyleLst><a:effectStyleLst>\#(effects)</a:effectStyleLst><a:bgFillStyleLst>\#(fill)\#(fill)\#(fill)</a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"#
  }

  // MARK: - Slides

  /// Positions in points on the 960 × 540 slide, shared with `SlideView`.
  enum Layout {
    static let margin: CGFloat = 54
    static let contentWidth: CGFloat = 852
    static let titleTop: CGFloat = 36
    static let titleHeight: CGFloat = 80
    static let accentTop: CGFloat = 122
    static let bodyTop: CGFloat = 144
    static let bodyHeight: CGFloat = 360
    static let coverTitleTop: CGFloat = 170
    static let coverTitleHeight: CGFloat = 120
    static let coverAccentTop: CGFloat = 302
    static let titleSize: CGFloat = 32
    static let coverTitleSize: CGFloat = 44
    static let bulletSize: CGFloat = 20
  }

  private static func slideXML(_ slide: DocumentSlide) -> String {
    var shapes: [String] = []
    if slide.isTitleSlide {
      shapes.append(textBox(
        id: 2, name: "Title",
        frame: CGRect(x: Layout.margin, y: Layout.coverTitleTop, width: Layout.contentWidth, height: Layout.coverTitleHeight),
        anchor: "b",
        paragraphs: [paragraph(slide.title, size: Layout.coverTitleSize, bold: true, color: textHex)]
      ))
      shapes.append(accentBar(id: 3, frame: CGRect(x: Layout.margin, y: Layout.coverAccentTop, width: 86, height: 4)))
    } else {
      shapes.append(textBox(
        id: 2, name: "Title",
        frame: CGRect(x: Layout.margin, y: Layout.titleTop, width: Layout.contentWidth, height: Layout.titleHeight),
        anchor: "b",
        paragraphs: [paragraph(slide.title, size: Layout.titleSize, bold: true, color: textHex)]
      ))
      shapes.append(accentBar(id: 3, frame: CGRect(x: Layout.margin, y: Layout.accentTop, width: 72, height: 3.6)))
      shapes.append(textBox(
        id: 4, name: "Body",
        frame: CGRect(x: Layout.margin, y: Layout.bodyTop, width: Layout.contentWidth, height: Layout.bodyHeight),
        anchor: "t",
        paragraphs: slide.bullets.map(bulletParagraph)
      ))
    }
    return header + #"<p:sld \#(namespaces)><p:cSld><p:spTree>\#(emptyTree)\#(shapes.joined())</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"#
  }

  private static func textBox(id: Int, name: String, frame: CGRect, anchor: String, paragraphs: [String]) -> String {
    let body = paragraphs.isEmpty ? #"<a:p><a:endParaRPr lang="ja-JP"/></a:p>"# : paragraphs.joined()
    return #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="\#(name)"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>\#(transform(frame))<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="\#(anchor)"><a:normAutofit/></a:bodyPr><a:lstStyle/>\#(body)</p:txBody></p:sp>"#
  }

  private static func accentBar(id: Int, frame: CGRect) -> String {
    #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="Accent"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>\#(transform(frame))<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="\#(accentHex)"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>"#
  }

  private static func paragraph(_ text: String, size: CGFloat, bold: Bool, color: String) -> String {
    #"<a:p>\#(run(text, size: size, bold: bold, color: color))</a:p>"#
  }

  private static func bulletParagraph(_ text: String) -> String {
    #"<a:p><a:pPr marL="342900" indent="-342900"><a:spcBef><a:spcPts val="1400"/></a:spcBef><a:buClr><a:srgbClr val="\#(accentHex)"/></a:buClr><a:buFont typeface="Arial"/><a:buChar char="•"/></a:pPr>\#(run(text, size: Layout.bulletSize, bold: false, color: textHex))</a:p>"#
  }

  private static func run(_ text: String, size: CGFloat, bold: Bool, color: String) -> String {
    #"<a:r><a:rPr lang="ja-JP" altLang="en-US" sz="\#(Int(size * 100))" b="\#(bold ? 1 : 0)" dirty="0"><a:solidFill><a:srgbClr val="\#(color)"/></a:solidFill></a:rPr><a:t>\#(escaped(text))</a:t></a:r>"#
  }

  private static func transform(_ frame: CGRect) -> String {
    #"<a:xfrm><a:off x="\#(emu(frame.minX))" y="\#(emu(frame.minY))"/><a:ext cx="\#(emu(frame.width))" cy="\#(emu(frame.height))"/></a:xfrm>"#
  }

  private static func emu(_ points: CGFloat) -> Int {
    Int((points * 12_700).rounded())
  }

  private static func escaped(_ text: String) -> String {
    // Control characters other than tab and newline are not allowed in XML.
    let cleaned = String(text.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" })
    return cleaned
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}
