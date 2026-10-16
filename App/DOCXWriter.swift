import Foundation

/// Editable Word paragraphs and tables. Office performs final pagination and font substitution.
enum DOCXWriter {
  static func data(for document: MemoraDocument) throws -> Data {
    guard document.plainText.count <= 150_000 else { throw OfficeArchiveReader.Failure.limit }
    var parts = ZipArchive()
    let ns = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    parts.add("[Content_Types].xml", text: """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
    """)
    parts.add("_rels/.rels", text: "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"word/document.xml\"/></Relationships>")
    parts.add("word/_rels/document.xml.rels", text: "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/styles\" Target=\"styles.xml\"/></Relationships>")
    parts.add("word/styles.xml", text: """
    <w:styles xmlns:w="\(ns)"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Yu Gothic"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:pPr><w:keepNext/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:pPr><w:keepNext/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style></w:styles>
    """)
    var body = paragraph(document.displayTitle, style: "Title")
    var rows: [[String]] = []
    func flushTable() {
      guard !rows.isEmpty else { return }
      body += "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders><w:top w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:insideH w:val=\"single\" w:sz=\"4\"/></w:tblBorders></w:tblPr>"
      for row in rows { body += "<w:tr>" + row.map { "<w:tc><w:tcPr/><w:p><w:r><w:t xml:space=\"preserve\">\(escape($0))</w:t></w:r></w:p></w:tc>" }.joined() + "</w:tr>" }
      body += "</w:tbl>"; rows = []
    }
    let content = document.kind == .document ? document.markdown : DocumentSlide.outline(of: document.slides)
    for line in content.components(separatedBy: .newlines) {
      if line.hasPrefix("|"), line.hasSuffix("|") {
        let cells = line.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { continue }
        guard cells.count <= 12 else { throw OfficeArchiveReader.Failure.limit }
        rows.append(cells); continue
      }
      flushTable()
      if line.hasPrefix("# ") { body += paragraph(String(line.dropFirst(2)), style: "Heading1") }
      else if line.hasPrefix("## ") { body += paragraph(String(line.dropFirst(3)), style: "Heading2") }
      else { body += paragraph(line) }
    }
    flushTable()
    body += "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/></w:sectPr>"
    parts.add("word/document.xml", text: "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"\(ns)\"><w:body>\(body)</w:body></w:document>")
    let data = parts.data()
    var check = try OfficeArchiveReader(data: data)
    _ = try OfficeDocumentExtraction.read(archive: &check, extension: "docx")
    return data
  }

  static func write(_ document: MemoraDocument) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(document.exportFileName)-\(UUID().uuidString.prefix(8)).docx")
    try data(for: document).write(to: url, options: .atomic)
    return url
  }

  static func escape(_ text: String) -> String {
    text.filter { $0 == "\n" || $0 == "\t" || $0.unicodeScalars.allSatisfy { $0.value >= 32 } }
      .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }

  private static func paragraph(_ text: String, style: String? = nil) -> String {
    let properties = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
    return "<w:p>\(properties)<w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
  }
}
