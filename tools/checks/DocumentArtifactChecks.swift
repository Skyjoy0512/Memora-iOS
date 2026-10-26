import Foundation

@main struct DocumentArtifactChecks {
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let doc = MemoraDocument(title: "提案書 {{title}}", kind: .document, markdown: "# 背景\n{{body}}\n\n| 項目 | 内容 |\n| --- | --- |\n| 費用 | 未確認 |")
    var legacy = doc
    legacy.artifactFileReference = "original.docx"
    legacy.artifactFormat = "DOCX"
    legacy.companyTemplateID = UUID()
    let legacyDecoded = try JSONDecoder().decode(MemoraDocument.self, from: JSONEncoder().encode(legacy))
    precondition(legacyDecoded.contentRevision == nil && !legacyDecoded.hasOutdatedArtifact)
    let edited = legacyDecoded.editing(title: "編集済み", body: "変更した本文")!
    precondition(edited.hasOutdatedArtifact && edited.contentRevision == 1 && edited.artifactRevision == nil)
    precondition(edited.artifactFileReference == legacy.artifactFileReference && edited.companyTemplateID == legacy.companyTemplateID)
    precondition(edited.editing(title: edited.title, body: edited.markdown) == edited)
    let editedReloaded = try JSONDecoder().decode(MemoraDocument.self, from: JSONEncoder().encode(edited))
    precondition(editedReloaded == edited)
    var invalid = legacy; invalid.contentRevision = Int.max
    precondition(invalid.editing(title: "変更", body: "変更") == nil)
    invalid.contentRevision = -1
    precondition(!invalid.hasValidRevisions && invalid.editing(title: "変更", body: "変更") == nil)
    let word = try DOCXWriter.data(for: doc)
    let slides = MemoraDocument(title: "報告", kind: .slides, slides: [DocumentSlide(title: "{{title}}", bullets: ["{{body}}"], notes: "保存メモ")])
    let titleOnlyEdit = slides.editing(title: "改題", body: DocumentSlide.outline(of: slides.slides))!
    precondition(titleOnlyEdit.slides == slides.slides && titleOnlyEdit.contentRevision == 1)
    let powerpoint = PPTXWriter.data(for: slides)
    for (format, bytes) in [(CompanyTemplate.Format.docx, word), (.pptx, powerpoint)] {
      let analysis = try CompanyTemplateEngine.analyze(bytes, format: format)
      precondition(analysis.placeholders == ["body", "title"] && analysis.isAvailable)
      let output = try CompanyTemplateEngine.fill(bytes, format: format, values: ["title": "日本語 & 検証", "body": "決定した内容 <編集可能>"])
      var before = try OfficeArchiveReader(data: bytes), after = try OfficeArchiveReader(data: output)
      precondition(before.partNames == after.partNames)
      for name in before.partNames {
        let first = try before.read(name), second = try after.read(name)
        if !["word/document.xml", "ppt/slides/slide1.xml"].contains(name) { precondition(first == second) }
      }
      var reloaded = try OfficeArchiveReader(data: output)
      let extracted = try OfficeDocumentExtraction.read(archive: &reloaded, extension: format.rawValue)
      precondition(extracted.blocks.map(\.text).joined().contains("日本語 & 検証"))
      try output.write(to: root.appendingPathComponent("generated." + format.rawValue))
      do { _ = try CompanyTemplateEngine.fill(bytes, format: format, values: ["title": "不足"]); preconditionFailure() } catch {}
      if format == .pptx {
        do { _ = try CompanyTemplateEngine.fill(bytes, format: format, values: ["title": String(repeating: "長", count: 121), "body": "内容"]); preconditionFailure() } catch {}
      }
      var splitPackage = ZipArchive()
      for name in before.partNames {
        let data = try before.read(name)
        let prefix = format == .docx ? "w" : "a"
        if name == (format == .docx ? "word/document.xml" : "ppt/slides/slide1.xml") {
          splitPackage.add(name, text: String(decoding: data, as: UTF8.self).replacingOccurrences(of: "{{title}}", with: "{{ti</\(prefix):t></\(prefix):r><\(prefix):r><\(prefix):t>tle}}"))
        } else { splitPackage.add(name, data: data) }
      }
      let splitData = splitPackage.data()
      let splitResult = try CompanyTemplateEngine.fill(splitData, format: format, values: ["title": "分割欄の日本語 & 検証", "body": "決定した内容 <編集可能>"])
      var splitBefore = try OfficeArchiveReader(data: splitData), splitAfter = try OfficeArchiveReader(data: splitResult)
      for name in splitBefore.partNames where name != (format == .docx ? "word/document.xml" : "ppt/slides/slide1.xml") {
        let original = try splitBefore.read(name), replaced = try splitAfter.read(name)
        precondition(original == replaced)
      }
      var splitReload = try OfficeArchiveReader(data: splitResult)
      let splitText = try OfficeDocumentExtraction.read(archive: &splitReload, extension: format.rawValue)
      precondition(splitText.blocks.map(\.text).joined().contains("分割欄の日本語 & 検証"))
      try splitData.write(to: root.appendingPathComponent("split-template." + format.rawValue))
      try splitResult.write(to: root.appendingPathComponent("split-runs." + format.rawValue))
    }
    var archive = try OfficeArchiveReader(data: word), split = ZipArchive()
    for name in archive.partNames {
      let data = try archive.read(name)
      if name == "word/document.xml" {
        split.add(name, text: String(decoding: data, as: UTF8.self).replacingOccurrences(of: "{{title}}", with: "{{ti</w:t></w:r><w:r><w:t>tle}}"))
      } else { split.add(name, data: data) }
    }
    let analysis = try CompanyTemplateEngine.analyze(split.data(), format: .docx)
    precondition(!analysis.unsupportedSplitMarkers && analysis.isAvailable && analysis.placeholders == ["body", "title"])
    try checkTextParts()
    do { _ = try CompanyTemplateEngine.analyze(Data("broken".utf8), format: .docx); preconditionFailure() } catch {}
    var long = doc; long.title = "長文"; long.markdown = (0..<300).map { "日本語の複数ページ用段落 \($0)" }.joined(separator: "\n")
    try DOCXWriter.data(for: long).write(to: root.appendingPathComponent("long.docx"))
    print("DocumentArtifactChecks: passed (real DOCX/PPTX, split runs, namespaces/entities/style/whitespace preservation, paragraph/break/field/tracked-change rejection, Japanese/tables/long flow, unchanged parts, reload; final Office rendering unverified)")
  }

  static func checkTextParts() throws {
    for (format, namespace, prefix) in [(CompanyTemplate.Format.docx, "http://schemas.openxmlformats.org/wordprocessingml/2006/main", "w"),
                                      (.pptx, "http://schemas.openxmlformats.org/drawingml/2006/main", "a"),
                                      (.docx, "http://purl.oclc.org/ooxml/wordprocessingml/main", "word"),
                                      (.pptx, "http://purl.oclc.org/ooxml/drawingml/main", "draw")] {
      func wrap(_ body: String) -> Data { Data(("<?xml version='1.0'?><root xmlns:\(prefix)='\(namespace)'>" + body + "</root>").utf8) }
      func run(_ text: String) -> String { "<\(prefix):r><\(prefix):t>\(text)</\(prefix):t></\(prefix):r>" }
      func paragraph(_ body: String) -> String { "<\(prefix):p>\(body)</\(prefix):p>" }
      for split in 1..<9 {
        let marker = "{{title}}", point = marker.index(marker.startIndex, offsetBy: split)
        let body = paragraph(run("前😀 &amp; " + marker[..<point]) + run(String(marker[point...]) + " 後"))
        let part = try OfficeTemplateTextPart(data: wrap(body), format: format)
        precondition(part.placeholders == ["title"] && !part.hasUnsupportedMarkers)
        let result = try part.filling(["title": " 日本語 <&> \"引用\" "])
        let parsed = try OfficeXMLDocument(data: result)
        let text = parsed.nodes.filter { $0.name == "t" }.map(\.text).joined()
        precondition(text == "前😀 &  日本語 <&> \"引用\"  後")
        precondition(parsed.nodes.filter { $0.name == "r" }.count == 2)
        precondition(String(decoding: result, as: UTF8.self).contains("xml:space=\"preserve\""))
      }
      let adjacent = try OfficeTemplateTextPart(data: wrap(paragraph(run("{{ti") + "<!-- <fake:t>ignored</fake:t> -->" + run("tle}}{{body}}{{title}}"))), format: format)
      let adjacentData = try adjacent.filling(["title": "値", "body": "本文"])
      let adjacentXML = try OfficeXMLDocument(data: adjacentData)
      precondition(adjacentXML.nodes.filter { $0.name == "t" }.map(\.text).joined() == "値本文値")
      precondition(String(decoding: adjacentData, as: UTF8.self).contains("<!-- <fake:t>ignored</fake:t> -->"))
      let quoted = wrap(paragraph("<\(prefix):r><\(prefix):rPr><\(prefix):b val='1'/></\(prefix):rPr><\(prefix):t xml:space='default' label='a > b'>&#123;&#123;title&#125;&#125;</\(prefix):t></\(prefix):r>"))
      let styled = try OfficeTemplateTextPart(data: quoted, format: format)
      let styledOutput = String(decoding: try styled.filling(["title": " 左右の空白 "]), as: UTF8.self)
      precondition(styledOutput.contains("<\(prefix):rPr><\(prefix):b val='1'/></\(prefix):rPr>") && styledOutput.contains("label='a > b'"))
      precondition(styledOutput.contains("xml:space=\"preserve\""))
      let untouched = wrap(paragraph(run("普通の &amp; 文字😀")))
      precondition(tryPartFill(untouched, format: format, values: [:]) == untouched)
      let bom = Data([0xef, 0xbb, 0xbf])
      let bomUntouched = bom + untouched
      precondition(tryPartFill(bomUntouched, format: format, values: [:]) == bomUntouched)
      let bomTemplate = bom + wrap(paragraph(run("{{title}}")))
      let bomResult = tryPartFill(bomTemplate, format: format, values: ["title": "日本語"])
      precondition(bomResult.starts(with: bom))
      let otherEncoding = Data(("<?xml version='1.0' encoding='ISO-8859-1'?>" + String(decoding: wrap(paragraph(run("{{title}}"))), as: UTF8.self).replacingOccurrences(of: "<?xml version='1.0'?>", with: "")).utf8)
      do { _ = try OfficeTemplateTextPart(data: otherEncoding, format: format); preconditionFailure("unsupported encoding accepted") } catch {}
      let lineBreaks = try OfficeTemplateTextPart(data: wrap(paragraph(run("始&#13;{{title}}終"))), format: format)
      let lineData = try lineBreaks.filling(["title": "行1\r\n行2"])
      let lineXML = try OfficeXMLDocument(data: lineData)
      precondition(lineXML.nodes.first(where: { $0.name == "t" })?.text == "始\r行1\r\n行2終")
      for invalid in ["\0", "\u{b}", "\u{fffe}"] {
        do { _ = try lineBreaks.filling(["title": invalid]); preconditionFailure("invalid XML character silently changed") } catch {}
      }
      let empty = try OfficeTemplateTextPart(data: wrap(paragraph(run("{{title}}"))), format: format)
      let emptyXML = try OfficeXMLDocument(data: empty.filling(["title": ""]))
      precondition(emptyXML.nodes.first(where: { $0.name == "t" })?.text == "")
      var denied = [paragraph(run("{{ti")) + paragraph(run("tle}}")),
                    paragraph(run("{{ti") + "<\(prefix):br/>" + run("tle}}")),
                    paragraph(run("{{ti") + "<\(prefix):tab/>" + run("tle}}")),
                    paragraph(run("{{unfinished")),
                    paragraph("<\(prefix):r><\(prefix):t>{{ti<!-- retained -->tle}}</\(prefix):t></\(prefix):r>")]
      if format == .docx {
        denied += [paragraph("<\(prefix):hyperlink>" + run("{{title}}") + "</\(prefix):hyperlink>"),
                   paragraph("<\(prefix):ins>" + run("{{title}}") + "</\(prefix):ins>"),
                   paragraph("<\(prefix):del><\(prefix):r><\(prefix):delText>{{title}}</\(prefix):delText></\(prefix):r></\(prefix):del>"),
                   paragraph("<\(prefix):r><\(prefix):fldChar \(prefix):fldCharType='begin'/></\(prefix):r>" + run("{{title}}") + "<\(prefix):r><\(prefix):fldChar \(prefix):fldCharType='end'/></\(prefix):r>")]
      } else {
        denied += [paragraph("<\(prefix):fld id='fixture'><\(prefix):t>{{title}}</\(prefix):t></\(prefix):fld>"),
                   paragraph("<\(prefix):r><\(prefix):rPr><\(prefix):hlinkClick/></\(prefix):rPr><\(prefix):t>{{title}}</\(prefix):t></\(prefix):r>")]
      }
      for body in denied {
        let part = try OfficeTemplateTextPart(data: wrap(body), format: format)
        precondition(part.hasUnsupportedMarkers)
        do { _ = try part.filling(["title": "値"]); preconditionFailure("unsupported boundary accepted") } catch {}
      }
      let repeating = try OfficeTemplateTextPart(data: wrap(paragraph(run(String(repeating: "{{title}}", count: 300)))), format: format)
      do { _ = try repeating.filling(["title": String(repeating: "長", count: 10_000)]); preconditionFailure("unbounded replacement accepted") } catch {}
    }
    let oldJSON = Data(#"{"placeholders":["title"],"features":[],"unsupportedSplitMarkers":true}"#.utf8)
    let old = try JSONDecoder().decode(CompanyTemplateEngine.Analysis.self, from: oldJSON)
    precondition(old.engineVersion == nil && !old.isAvailable)
    let oversized = MemoraDocument(title: "欄数の上限", kind: .document,
      markdown: (0..<31).map { "{{field\($0)}}" }.joined(separator: "\n"))
    let oversizedData = try DOCXWriter.data(for: oversized)
    do { _ = try CompanyTemplateEngine.analyze(oversizedData, format: .docx); preconditionFailure("metadata incompatible with backup accepted") } catch {}
  }

  static func tryPartFill(_ data: Data, format: CompanyTemplate.Format, values: [String: String]) -> Data {
    try! OfficeTemplateTextPart(data: data, format: format).filling(values)
  }
}
