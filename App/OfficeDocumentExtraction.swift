import Foundation

/// Text-only OOXML support. Layout, images, notes, macros and spreadsheet
/// recalculation are deliberately outside this local reader's contract.
enum OfficeDocumentExtraction {
  struct Result: Sendable {
    var blocks: [ProjectSourceText]
    var notice: String
  }

  private static let word: Set<String> = ["http://schemas.openxmlformats.org/wordprocessingml/2006/main", "http://purl.oclc.org/ooxml/wordprocessingml/main"]
  private static let presentation: Set<String> = ["http://schemas.openxmlformats.org/presentationml/2006/main", "http://purl.oclc.org/ooxml/presentationml/main"]
  private static let drawing: Set<String> = ["http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main"]
  private static let spreadsheet: Set<String> = ["http://schemas.openxmlformats.org/spreadsheetml/2006/main", "http://purl.oclc.org/ooxml/spreadsheetml/main"]
  private static let packageRelationships: Set<String> = ["http://schemas.openxmlformats.org/package/2006/relationships"]
  private static let contentTypes: Set<String> = ["http://schemas.openxmlformats.org/package/2006/content-types"]
  private static let relationshipPrefixes = ["http://schemas.openxmlformats.org/officeDocument/2006/relationships/", "http://purl.oclc.org/ooxml/officeDocument/relationships/"]
  private static let maximumCharacters = 80_000

  static func read(_ url: URL) throws -> Result {
    var archive = try OfficeArchiveReader(url: url)
    return try read(archive: &archive, extension: url.pathExtension.lowercased())
  }

  static func read(archive: inout OfficeArchiveReader, extension suffix: String) throws -> Result {
    let roots = try relationships(part: nil, archive: &archive).values.filter { isType($0.type, "officeDocument") }
    guard roots.count == 1, let root = roots.first, let main = root.target else { throw OfficeArchiveReader.Failure.unsupported }
    let expected: String
    switch suffix {
    case "docx": expected = "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
    case "pptx": expected = "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"
    case "xlsx": expected = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
    default: throw OfficeArchiveReader.Failure.unsupported
    }
    let types = try xml("[Content_Types].xml", archive: &archive, root: "Types", namespaces: contentTypes)
    guard types.children(0, named: "Override", namespaces: contentTypes).contains(where: {
      types.nodes[$0].attributes["PartName"] == "/" + main && types.nodes[$0].attributes["ContentType"] == expected
    }) else { throw OfficeArchiveReader.Failure.unsupported }
    var budget = TextBudget()
    switch suffix {
    case "docx":
      let document = try xml(main, archive: &archive, root: "document", namespaces: word)
      guard let body = document.children(0, named: "body", namespaces: word).first else { throw OfficeArchiveReader.Failure.invalid }
      let paragraphs = document.descendants(body, named: "p", namespaces: word)
      for paragraph in paragraphs {
        try Task.checkCancellation()
        budget.append(document.text(paragraph, namespaces: word))
        if budget.isFull { break }
      }
      return budget.result("Wordの本文・表の文字を読み取りました。画像、ヘッダー、脚注、コメント、レイアウトは解析していません。")
    case "pptx":
      let document = try xml(main, archive: &archive, root: "presentation", namespaces: presentation)
      guard let list = document.children(0, named: "sldIdLst", namespaces: presentation).first else { throw OfficeArchiveReader.Failure.invalid }
      let slides = document.children(list, named: "sldId", namespaces: presentation)
      let links = try relationships(part: main, archive: &archive)
      for (number, slide) in slides.prefix(50).enumerated() {
        try Task.checkCancellation()
        guard let id = document.nodes[slide].relationshipID, let link = links[id],
              isType(link.type, "slide"), let path = link.target else { throw OfficeArchiveReader.Failure.invalid }
        let content = try xml(path, archive: &archive, root: "sld", namespaces: presentation)
        let paragraphs = content.descendants(0, named: "p", namespaces: drawing)
        let text = paragraphs.map { content.text($0, namespaces: drawing) }.filter { !$0.isEmpty }.joined(separator: "\n")
        if !text.isEmpty { budget.append("スライド \(number + 1)\n" + text) }
        if budget.isFull { break }
      }
      if slides.count > 50 { budget.notices.append("先頭50スライドまでを読み取りました。") }
      return budget.result("PowerPointのスライド順に文字を読み取りました。画像、グラフ、埋め込み資料、発表者ノートは解析していません。")
    case "xlsx":
      try readWorkbook(main, archive: &archive, budget: &budget)
      return budget.result("Excelのシート名・セル番地・保存された値を読み取りました。数式の再計算、日付や表示形式の変換、画像、グラフは解析していません。非表示の行・列を含む場合があります。")
    default: throw OfficeArchiveReader.Failure.unsupported
    }
  }

  private static func readWorkbook(_ main: String, archive: inout OfficeArchiveReader, budget: inout TextBudget) throws {
    let workbook = try xml(main, archive: &archive, root: "workbook", namespaces: spreadsheet)
    guard let list = workbook.children(0, named: "sheets", namespaces: spreadsheet).first else { throw OfficeArchiveReader.Failure.invalid }
    let sheets = workbook.children(list, named: "sheet", namespaces: spreadsheet)
    let links = try relationships(part: main, archive: &archive)
    let stringLinks = links.values.filter { isType($0.type, "sharedStrings") }
    guard stringLinks.count <= 1 else { throw OfficeArchiveReader.Failure.invalid }
    var strings: [String] = []
    if let link = stringLinks.first {
      guard let path = link.target else { throw OfficeArchiveReader.Failure.invalid }
      let table = try xml(path, archive: &archive, root: "sst", namespaces: spreadsheet)
      strings = table.children(0, named: "si", namespaces: spreadsheet).map { table.text($0, namespaces: spreadsheet) }
    }
    var cellsRead = 0
    for sheet in sheets.prefix(20) {
      try Task.checkCancellation()
      let node = workbook.nodes[sheet]
      if node.attributes["state"] == "hidden" || node.attributes["state"] == "veryHidden" {
        budget.notices.append("非表示のシートは読み取っていません。"); continue
      }
      guard let name = node.attributes["name"], let id = node.relationshipID,
            let link = links[id], isType(link.type, "worksheet"), let path = link.target else { throw OfficeArchiveReader.Failure.invalid }
      let document = try xml(path, archive: &archive, root: "worksheet", namespaces: spreadsheet)
      guard let data = document.children(0, named: "sheetData", namespaces: spreadsheet).first else { throw OfficeArchiveReader.Failure.invalid }
      for row in document.children(data, named: "row", namespaces: spreadsheet) {
        try Task.checkCancellation()
        var values: [String] = []
        var reachedCellLimit = false
        for cell in document.children(row, named: "c", namespaces: spreadsheet) {
          cellsRead += 1
          if cellsRead > 5_000 { reachedCellLimit = true; break }
          let cellNode = document.nodes[cell]
          guard let address = cellNode.attributes["r"], validCellAddress(address) else { throw OfficeArchiveReader.Failure.invalid }
          let value = document.children(cell, named: "v", namespaces: spreadsheet).first.map { document.nodes[$0].text }
          let text: String
          switch cellNode.attributes["t"] ?? "n" {
          case "s":
            guard let value, let index = Int(value), strings.indices.contains(index) else { throw OfficeArchiveReader.Failure.invalid }
            text = strings[index]
          case "inlineStr": text = document.text(cell, namespaces: spreadsheet)
          case "b":
            guard value == "0" || value == "1" else { throw OfficeArchiveReader.Failure.invalid }
            text = value == "1" ? "TRUE" : "FALSE"
          case "n", "str", "d", "e": text = value ?? ""
          default: throw OfficeArchiveReader.Failure.unsupported
          }
          if !text.isEmpty { values.append(address + ": " + text) }
        }
        // A search excerpt must keep the sheet and related cells together.
        if !values.isEmpty { budget.append("シート: " + name + "\n" + values.joined(separator: "\n")) }
        if reachedCellLimit { budget.notices.append("先頭5,000セルまでを読み取りました。"); return }
        if budget.isFull { return }
      }
    }
    if sheets.count > 20 { budget.notices.append("先頭20シートまでを読み取りました。") }
  }

  private static func validCellAddress(_ address: String) -> Bool {
    guard address.utf8.count <= 10 else { return false }
    let letters = address.prefix { $0 >= "A" && $0 <= "Z" }
    let digits = address.dropFirst(letters.count)
    guard !letters.isEmpty, letters.count <= 3, !digits.isEmpty, digits.first != "0",
          digits.allSatisfy({ $0 >= "0" && $0 <= "9" }), let row = Int(digits), row <= 1_048_576 else { return false }
    let column = letters.utf8.reduce(0) { $0 * 26 + Int($1) - 64 }
    return column <= 16_384
  }

  private static func xml(_ part: String, archive: inout OfficeArchiveReader, root: String, namespaces: Set<String>) throws -> OfficeXMLDocument {
    let document = try OfficeXMLDocument(data: archive.read(part))
    guard document.matches(0, root, namespaces: namespaces) else { throw OfficeArchiveReader.Failure.invalid }
    return document
  }

  private static func relationships(part: String?, archive: inout OfficeArchiveReader) throws -> [String: Relationship] {
    let directory = part.map { ($0 as NSString).deletingLastPathComponent } ?? ""
    let file = part.map { ($0 as NSString).lastPathComponent + ".rels" } ?? ".rels"
    let path = (directory.isEmpty ? "" : directory + "/") + "_rels/" + file
    let document = try xml(path, archive: &archive, root: "Relationships", namespaces: packageRelationships)
    var result: [String: Relationship] = [:]
    for index in document.children(0, named: "Relationship", namespaces: packageRelationships) {
      let attributes = document.nodes[index].attributes
      guard let id = attributes["Id"], !id.isEmpty, result[id] == nil,
            let type = attributes["Type"], let target = attributes["Target"] else { throw OfficeArchiveReader.Failure.invalid }
      let external = attributes["TargetMode"] == "External"
      result[id] = Relationship(type: type, target: external ? nil : resolve(target, directory: directory))
    }
    return result
  }

  private static func resolve(_ target: String, directory: String) -> String? {
    guard !target.isEmpty, !target.contains(":"), !target.contains("\\"), !target.contains("%"),
          !target.contains("?"), !target.contains("#"), !target.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
    var parts = target.hasPrefix("/") ? [] : directory.split(separator: "/").map(String.init)
    let relative = target.hasPrefix("/") ? String(target.dropFirst()) : target
    for component in relative.split(separator: "/", omittingEmptySubsequences: false) {
      if component == ".." {
        guard !parts.isEmpty else { return nil }; parts.removeLast()
      } else if component != "." {
        guard !component.isEmpty else { return nil }; parts.append(String(component))
      }
    }
    return parts.isEmpty ? nil : parts.joined(separator: "/")
  }

  private static func isType(_ value: String, _ name: String) -> Bool {
    relationshipPrefixes.contains { value == $0 + name }
  }

  private struct Relationship {
    var type: String
    var target: String?
  }

  private struct TextBudget {
    var blocks: [ProjectSourceText] = []
    var notices: [String] = []
    var remaining = maximumCharacters
    // JSON may escape each byte. Stay below the existing 2MiB source reader
    // even with combining characters, control escapes and block metadata.
    var remainingBytes = 256 * 1024
    var isFull: Bool { remaining == 0 || remainingBytes == 0 || blocks.count >= 2_000 }

    mutating func append(_ text: String) {
      guard !text.isEmpty, !isFull else { return }
      var value = String(text.prefix(remaining))
      let byteLimited = value.utf8.count > remainingBytes
      if byteLimited {
        var bytes = Data(value.utf8.prefix(remainingBytes))
        while !bytes.isEmpty, String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        value = String(data: bytes, encoding: .utf8) ?? ""
      }
      guard !value.isEmpty else { remainingBytes = 0; return }
      blocks.append(ProjectSourceText(text: value))
      remaining -= value.count
      remainingBytes = byteLimited ? 0 : remainingBytes - value.utf8.count
      if isFull { notices.append("本文は80,000文字・256KB・2,000ブロックまでを読み取りました。") }
    }

    func result(_ notice: String) -> Result {
      let messages = [notice] + Array(Set(notices)).sorted() + (blocks.isEmpty ? ["参照できる文字がありません。"] : [])
      return Result(blocks: blocks, notice: messages.joined(separator: " "))
    }
  }
}
