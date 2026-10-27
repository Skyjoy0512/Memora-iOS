import CoreGraphics
import Foundation

/// Editable text with the same derived pages used by screen and PDF.
enum PPTXWriter {
  /// 16:9 in EMU; one point is 12,700 EMU, so this is `SlideView`'s 960 × 540.
  static let slideWidth = 12_192_000
  static let slideHeight = 6_858_000
  static let accentHex = "0D0D0D"
  static let textHex = "0D0D0D"
  static let secondaryHex = "6E6E73"

  static func data(for document: MemoraDocument) -> Data {
    var archive = ZipArchive()
    let slides = SlidePageLayout.pages(for: document).map { page in
      var page = page
      if let text = page.readingText {
        page.notes += (page.notes.isEmpty ? "" : "\n\n") + text.joined(separator: "\n")
      }
      return page
    }
    let noteNumbers = slides.enumerated().compactMap { $0.element.notes.isEmpty ? nil : $0.offset + 1 }

    archive.add("[Content_Types].xml", text: contentTypes(slideCount: slides.count, noteNumbers: noteNumbers))
    archive.add("_rels/.rels", text: rootRelationships)
    archive.add("ppt/presentation.xml", text: presentation(slideCount: slides.count, hasNotes: !noteNumbers.isEmpty))
    archive.add("ppt/_rels/presentation.xml.rels", text: presentationRelationships(slideCount: slides.count, hasNotes: !noteNumbers.isEmpty))
    archive.add("ppt/slideMasters/slideMaster1.xml", text: slideMaster)
    archive.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", text: slideMasterRelationships)
    archive.add("ppt/slideLayouts/slideLayout1.xml", text: slideLayout)
    archive.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", text: slideLayoutRelationships)
    archive.add("ppt/theme/theme1.xml", text: theme)
    if !noteNumbers.isEmpty {
      archive.add("ppt/notesMasters/notesMaster1.xml", text: notesMaster)
      archive.add("ppt/notesMasters/_rels/notesMaster1.xml.rels", text: notesMasterRelationships)
    }
    for (index, slide) in slides.enumerated() {
      archive.add("ppt/slides/slide\(index + 1).xml", text: slideXML(slide))
      archive.add("ppt/slides/_rels/slide\(index + 1).xml.rels", text: slideRelationships(number: index + 1, hasNotes: !slide.notes.isEmpty))
      if !slide.notes.isEmpty {
        archive.add("ppt/notesSlides/notesSlide\(index + 1).xml", text: notesXML(slide.notes))
        archive.add("ppt/notesSlides/_rels/notesSlide\(index + 1).xml.rels", text: notesRelationships(number: index + 1))
      }
    }
    return archive.data()
  }

  /// Writes the file to the temporary folder for the share sheet.
  static func write(_ document: MemoraDocument) throws -> URL {
    try PresentationExportCheck.validate(document)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(document.exportFileName)-\(UUID().uuidString.prefix(8)).pptx")
    try data(for: document).write(to: url, options: .atomic)
    return url
  }

  // MARK: - Package parts

  private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
  private static let namespaces = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main""#
  private static let relationshipBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

  private static func contentTypes(slideCount: Int, noteNumbers: [Int]) -> String {
    let slides = (1...slideCount).map {
      #"<Override PartName="/ppt/slides/slide\#($0).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>"#
    }.joined()
    let notes = noteNumbers.map {
      #"<Override PartName="/ppt/notesSlides/notesSlide\#($0).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>"#
    }.joined()
    let master = noteNumbers.isEmpty ? "" : #"<Override PartName="/ppt/notesMasters/notesMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/>"#
    return header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>"# + slides + notes + master + "</Types>"
  }

  private static var rootRelationships: String {
    header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/officeDocument" Target="ppt/presentation.xml"/></Relationships>"#
  }

  private static func presentation(slideCount: Int, hasNotes: Bool) -> String {
    let ids = (1...slideCount).map { #"<p:sldId id="\#(255 + $0)" r:id="rId\#($0 + 2)"/>"# }.joined()
    let notes = hasNotes ? #"<p:notesMasterIdLst><p:notesMasterId r:id="rIdNotesMaster"/></p:notesMasterIdLst>"# : ""
    return header + #"<p:presentation \#(namespaces)><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\#(notes)<p:sldIdLst>\#(ids)</p:sldIdLst><p:sldSz cx="\#(slideWidth)" cy="\#(slideHeight)"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#
  }

  private static func presentationRelationships(slideCount: Int, hasNotes: Bool) -> String {
    let slides = (1...slideCount).map {
      #"<Relationship Id="rId\#($0 + 2)" Type="\#(relationshipBase)/slide" Target="slides/slide\#($0).xml"/>"#
    }.joined()
    let notes = hasNotes ? #"<Relationship Id="rIdNotesMaster" Type="\#(relationshipBase)/notesMaster" Target="notesMasters/notesMaster1.xml"/>"# : ""
    return header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/slideMaster" Target="slideMasters/slideMaster1.xml"/><Relationship Id="rId2" Type="\#(relationshipBase)/theme" Target="theme/theme1.xml"/>"# + slides + notes + "</Relationships>"
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

  private static func slideRelationships(number: Int, hasNotes: Bool) -> String {
    let notes = hasNotes ? #"<Relationship Id="rIdNotes" Type="\#(relationshipBase)/notesSlide" Target="../notesSlides/notesSlide\#(number).xml"/>"# : ""
    return header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>\#(notes)</Relationships>"#
  }

  private static var notesMaster: String {
    header + #"<p:notesMaster \#(namespaces)><p:cSld><p:spTree>\#(emptyTree)</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:notesStyle><a:lvl1pPr><a:defRPr sz="1200"/></a:lvl1pPr></p:notesStyle></p:notesMaster>"#
  }

  private static var notesMasterRelationships: String {
    header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/theme" Target="../theme/theme1.xml"/></Relationships>"#
  }

  private static func notesRelationships(number: Int) -> String {
    header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\#(relationshipBase)/notesMaster" Target="../notesMasters/notesMaster1.xml"/><Relationship Id="rId2" Type="\#(relationshipBase)/slide" Target="../slides/slide\#(number).xml"/></Relationships>"#
  }

  private static func notesXML(_ notes: String) -> String {
    let normalized = notes.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let paragraphs = normalized.components(separatedBy: "\n").map {
      "<a:p>" + run($0, size: 12, bold: false, color: textHex) + "</a:p>"
    }.joined()
    let frame = CGRect(x: 54, y: 342, width: 432, height: 324)
    let body = #"<p:sp><p:nvSpPr><p:cNvPr id="2" name="Speaker notes"/><p:cNvSpPr txBox="1"/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr>\#(transform(frame))</p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>\#(paragraphs)</p:txBody></p:sp>"#
    return header + #"<p:notes \#(namespaces)><p:cSld><p:spTree>\#(emptyTree)\#(body)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"#
  }

  private static var theme: String {
    let font = #"<a:latin typeface="Helvetica Neue"/><a:ea typeface=""/><a:cs typeface=""/><a:font script="Jpan" typeface="Hiragino Sans"/>"#
    let fill = #"<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>"#
    let colors = [
      ("dk1", textHex), ("lt1", "FFFFFF"), ("dk2", "3A3A3C"), ("lt2", "F2F2F7"),
      ("accent1", accentHex), ("accent2", "303030"), ("accent3", "5D5D5D"), ("accent4", "767676"),
      ("accent5", "AFAFAF"), ("accent6", "E5E5E5"), ("hlink", accentHex), ("folHlink", "5D5D5D")
    ].map { #"<a:\#($0.0)><a:srgbClr val="\#($0.1)"/></a:\#($0.0)>"# }.joined()
    let lines = [6350, 12700, 19050].map { #"<a:ln w="\#($0)">\#(fill)</a:ln>"# }.joined()
    let effects = String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3)
    return header + #"<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Memora"><a:themeElements><a:clrScheme name="Memora">\#(colors)</a:clrScheme><a:fontScheme name="Memora"><a:majorFont>\#(font)</a:majorFont><a:minorFont>\#(font)</a:minorFont></a:fontScheme><a:fmtScheme name="Memora"><a:fillStyleLst>\#(fill)\#(fill)\#(fill)</a:fillStyleLst><a:lnStyleLst>\#(lines)</a:lnStyleLst><a:effectStyleLst>\#(effects)</a:effectStyleLst><a:bgFillStyleLst>\#(fill)\#(fill)\#(fill)</a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"#
  }

  // MARK: - Slides

  private typealias Layout = SlidePageLayout

  private static func slideXML(_ slide: SlidePage) -> String {
    if let elements = slide.elements {
      return header + #"<p:sld \#(namespaces)><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>\#(emptyTree)\#(PresentationOOXML.shapes(elements))</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"#
    }
    var shapes: [String] = []
    let titleSize = slide.isCover ? Layout.coverTitleSize : Layout.titleSize
    let titleLineHeight = slide.isCover ? Layout.coverLineHeight : Layout.titleLineHeight
    shapes.append(textBox(
      id: 2, name: "Title",
      frame: CGRect(x: Layout.margin, y: slide.isCover ? Layout.coverTitleTop : Layout.titleTop,
                    width: Layout.contentWidth, height: CGFloat(slide.titleLines.count) * titleLineHeight),
      anchor: "t", paragraphs: [lineParagraph(slide.titleLines, size: titleSize, bold: true, lineHeight: titleLineHeight)]
    ))
    var top = Layout.bodyTop
    for (index, bullet) in slide.bullets.enumerated() {
      let height = CGFloat(bullet.lines.count) * Layout.bulletLineHeight
      shapes.append(textBox(
        id: index + 3, name: "Point \(bullet.sourceIndex + 1)",
        frame: CGRect(x: Layout.margin, y: top, width: Layout.contentWidth, height: height),
        anchor: "t",
        paragraphs: [lineParagraph(bullet.lines, size: Layout.bulletSize, bold: false,
                                   lineHeight: Layout.bulletLineHeight, bullet: bullet.showsMarker)]
      ))
      top += height + Layout.bulletGap
    }
    return header + #"<p:sld \#(namespaces)><p:cSld><p:spTree>\#(emptyTree)\#(shapes.joined())</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"#
  }

  private static func textBox(id: Int, name: String, frame: CGRect, anchor: String, paragraphs: [String]) -> String {
    let body = paragraphs.isEmpty ? #"<a:p><a:endParaRPr lang="ja-JP"/></a:p>"# : paragraphs.joined()
    return #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="\#(name)"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>\#(transform(frame))<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="\#(anchor)"><a:noAutofit/></a:bodyPr><a:lstStyle/>\#(body)</p:txBody></p:sp>"#
  }

  private static func lineParagraph(_ lines: [String], size: CGFloat, bold: Bool,
                                    lineHeight: CGFloat, bullet: Bool? = nil) -> String {
    let indent = bullet == nil ? "" : #" marL="\#(emu(Layout.bulletIndent))" indent="\#(bullet == true ? -emu(Layout.bulletIndent) : 0)""#
    let marker = bullet == true ? #"<a:buFont typeface="Arial"/><a:buChar char="•"/>"# : "<a:buNone/>"
    let content = lines.map { run(Layout.visibleLine($0), size: size, bold: bold, color: textHex) }.joined(separator: "<a:br/>")
    return #"<a:p><a:pPr\#(indent)><a:lnSpc><a:spcPts val="\#(Int(lineHeight * 100))"/></a:lnSpc>\#(marker)</a:pPr>\#(content)<a:endParaRPr sz="\#(Int(size * 100))"/></a:p>"#
  }

  private static func run(_ text: String, size: CGFloat, bold: Bool, color: String) -> String {
    #"<a:r><a:rPr lang="ja-JP" altLang="en-US" sz="\#(Int(size * 100))" b="\#(bold ? 1 : 0)" dirty="0"><a:solidFill><a:srgbClr val="\#(color)"/></a:solidFill><a:latin typeface="Helvetica Neue"/><a:ea typeface="Hiragino Sans"/></a:rPr><a:t xml:space="preserve">\#(escaped(text))</a:t></a:r>"#
  }

  private static func transform(_ frame: CGRect) -> String {
    #"<a:xfrm><a:off x="\#(emu(frame.minX))" y="\#(emu(frame.minY))"/><a:ext cx="\#(emu(frame.width))" cy="\#(emu(frame.height))"/></a:xfrm>"#
  }

  private static func emu(_ points: CGFloat) -> Int {
    Int((points * 12_700).rounded())
  }

  private static func escaped(_ text: String) -> String {
    // Control characters other than tab and newline are not allowed in XML.
    let cleaned = String(text.unicodeScalars.filter {
      $0 == "\t" || $0 == "\n" || $0 == "\r" || (0x20...0xD7FF).contains($0.value)
        || (0xE000...0xFFFD).contains($0.value) || (0x10000...0x10FFFF).contains($0.value)
    })
    return cleaned
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}
