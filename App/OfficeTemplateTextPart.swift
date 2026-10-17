import Foundation

/// Maps validated elements to original ranges; the surrounding XML is never serialized again.
struct OfficeTemplateTextPart {
  var document: OfficeXMLDocument
  var placeholders: [String]
  var hasUnsupportedMarkers: Bool
  private var source: String
  private var groups: [[Int]]
  private var openings: [Int: NSRange]
  private var contents: [Int: NSRange]
  private static let marker = try! NSRegularExpression(pattern: #"\{\{([A-Za-z][A-Za-z0-9_]{0,39})\}\}"#)
  private static let encoding = try! NSRegularExpression(pattern: #"<\?xml\s[^?]*\bencoding\s*=\s*['\"]([^'\"]+)['\"]"#)
  private static let tokens = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|</?[A-Za-z_][A-Za-z0-9_.:-]*(?:[^\"'<>]|\"[^\"]*\"|'[^']*')*>"#)
  private static let word: Set<String> = ["http://schemas.openxmlformats.org/wordprocessingml/2006/main", "http://purl.oclc.org/ooxml/wordprocessingml/main"]
  private static let drawing: Set<String> = ["http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main"]

  init(data: Data, format: CompanyTemplate.Format) throws {
    let document = try OfficeXMLDocument(data: data)
    self.document = document
    // Validation above rejects invalid UTF-8. This decoder also keeps a leading BOM in the original ranges.
    let source = String(decoding: data, as: UTF8.self)
    self.source = source
    let raw = source as NSString
    if let encoding = Self.encoding.firstMatch(in: source, range: NSRange(location: 0, length: raw.length)) {
      guard raw.substring(with: encoding.range(at: 1)).lowercased() == "utf-8" else { throw CompanyTemplateEngine.Failure.unsupported }
    }
    var openings: [Int: NSRange] = [:], contents: [Int: NSRange] = [:]
    var stack: [(index: Int, name: String, content: Int)] = []
    var next = 0
    for token in Self.tokens.matches(in: source, range: NSRange(location: 0, length: raw.length)) {
      try Task.checkCancellation()
      let text = raw.substring(with: token.range)
      if text.hasPrefix("<!--") || text.hasPrefix("<?") { continue }
      guard !text.hasPrefix("<!") else { throw CompanyTemplateEngine.Failure.unsupported }
      let closing = text.hasPrefix("</")
      let name = String(text.dropFirst(closing ? 2 : 1).prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" })
      if closing {
        guard let last = stack.popLast(), last.name == name else { throw CompanyTemplateEngine.Failure.unsupported }
        contents[last.index] = NSRange(location: last.content, length: token.range.location - last.content)
      } else {
        guard next < document.nodes.count, document.nodes[next].name == name.split(separator: ":").last.map(String.init) else {
          throw CompanyTemplateEngine.Failure.unsupported
        }
        openings[next] = token.range
        if !text.hasSuffix("/>") { stack.append((next, name, NSMaxRange(token.range))) }
        next += 1
      }
    }
    guard next == document.nodes.count, stack.isEmpty else { throw CompanyTemplateEngine.Failure.unsupported }
    self.openings = openings; self.contents = contents
    let namespaces = format == .docx ? Self.word : Self.drawing
    var parents: [Int: Int] = [:]
    for index in document.nodes.indices {
      for child in document.nodes[index].children { parents[child] = index }
    }
    var excluded = Set<Int>(), fieldDepth = 0
    for (index, content) in contents where document.nodes[index].name == "t" && raw.substring(with: content).contains("<") {
      excluded.insert(index)
    }
    for index in document.nodes.indices {
      let node = document.nodes[index]
      if format == .docx, Self.word.contains(node.namespace), node.name == "fldChar" {
        let type = node.attributes.first { $0.key.split(separator: ":").last == "fldCharType" }?.value
        if type == "begin" { fieldDepth += 1 }
        if type == "end" { fieldDepth = max(0, fieldDepth - 1) }
      }
      if fieldDepth > 0 { excluded.insert(index) }
      if let parent = parents[index], excluded.contains(parent) { excluded.insert(index) }
      if ["del", "moveFrom", "ins", "moveTo", "sdt", "hyperlink", "fldSimple", "AlternateContent"].contains(node.name) { excluded.insert(index) }
      if ["hlinkClick", "hlinkMouseOver"].contains(node.name) {
        var ancestor = parents[index]
        while let parent = ancestor, document.nodes[parent].name != "p" {
          excluded.insert(parent); ancestor = parents[parent]
        }
      }
    }
    var groups: [[Int]] = []
    for paragraph in document.nodes.indices where document.matches(paragraph, "p", namespaces: namespaces) && !excluded.contains(paragraph) {
      var group: [Int] = []
      func flush() { if !group.isEmpty { groups.append(group); group = [] } }
      for run in document.nodes[paragraph].children {
        guard document.matches(run, "r", namespaces: namespaces), !excluded.contains(run) else { flush(); continue }
        for child in document.nodes[run].children {
          if document.matches(child, "rPr", namespaces: namespaces) { continue }
          if document.matches(child, "t", namespaces: namespaces), !excluded.contains(child), document.nodes[child].children.isEmpty {
            group.append(child)
          } else { flush() }
        }
      }
      flush()
    }
    self.groups = groups
    let allText = document.nodes.filter { ["t", "delText", "instrText"].contains($0.name) }.map(\.text).joined()
    let supported = groups.flatMap { Self.names(in: $0.map { document.nodes[$0].text }.joined()) }.sorted()
    let remainder = Self.marker.stringByReplacingMatches(in: allText, range: NSRange(allText.startIndex..., in: allText), withTemplate: "")
    placeholders = Array(Set(supported)).sorted()
    hasUnsupportedMarkers = Self.names(in: allText).sorted() != supported || remainder.contains("{{")
  }

  func filling(_ values: [String: String]) throws -> Data {
    guard !hasUnsupportedMarkers else { throw CompanyTemplateEngine.Failure.unsupported }
    var changed: [Int: NSMutableString] = [:]
    var byteReservation = source.utf8.count
    let escapedLengths = try values.mapValues { try Self.escapeText($0).utf8.count }
    for group in groups {
      try Task.checkCancellation()
      var spans: [(index: Int, range: NSRange)] = [], offset = 0
      let text = group.map { document.nodes[$0].text }.joined()
      for index in group {
        let length = (document.nodes[index].text as NSString).length
        spans.append((index, NSRange(location: offset, length: length))); offset += length
      }
      for match in Self.marker.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
        let name = (text as NSString).substring(with: match.range(at: 1))
        guard let value = values[name] else { throw CompanyTemplateEngine.Failure.fields }
        // Reserve before growing any string; repeated markers must not multiply a bounded value without a limit.
        let addition = (escapedLengths[name] ?? 0) + 64
        guard addition <= OfficeArchiveReader.maximumPartBytes,
              byteReservation <= OfficeArchiveReader.maximumPartBytes - addition else { throw OfficeArchiveReader.Failure.limit }
        byteReservation += addition
        var inserted = false
        for span in spans {
          let overlap = NSIntersectionRange(span.range, match.range)
          guard overlap.length > 0 else { continue }
          let mutable = changed[span.index] ?? NSMutableString(string: document.nodes[span.index].text)
          mutable.replaceCharacters(in: NSRange(location: overlap.location - span.range.location, length: overlap.length), with: inserted ? "" : value)
          changed[span.index] = mutable; inserted = true
        }
      }
    }
    var edits: [(range: NSRange, value: String)] = []
    let raw = source as NSString
    for (index, value) in changed where value as String != document.nodes[index].text {
      guard let content = contents[index], let opening = openings[index] else { throw CompanyTemplateEngine.Failure.unsupported }
      edits.append((content, try Self.escapeText(value as String)))
      if value.length > 0, (value as String).first?.isWhitespace == true || (value as String).last?.isWhitespace == true {
        var tag = raw.substring(with: opening)
        if let space = document.nodes[index].attributes["xml:space"] {
          guard ["default", "preserve"].contains(space) else { throw CompanyTemplateEngine.Failure.unsupported }
          if space == "default" {
            tag = tag.replacingOccurrences(of: #"xml:space\s*=\s*(['\"])default\1"#, with: "xml:space=\"preserve\"", options: .regularExpression)
          }
        } else { tag.insert(contentsOf: " xml:space=\"preserve\"", at: tag.index(before: tag.endIndex)) }
        if tag != raw.substring(with: opening) { edits.append((opening, tag)) }
      }
    }
    let output = NSMutableString(string: source)
    for edit in edits.sorted(by: { $0.range.location > $1.range.location }) { output.replaceCharacters(in: edit.range, with: edit.value) }
    let data = Data((output as String).utf8)
    _ = try OfficeXMLDocument(data: data)
    return data
  }

  private static func names(in text: String) -> [String] {
    marker.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range(at: 1)) }
  }

  private static func escapeText(_ text: String) throws -> String {
    guard text.unicodeScalars.allSatisfy({ scalar in
      [9, 10, 13].contains(scalar.value) || (32...0xd7ff).contains(scalar.value)
        || (0xe000...0xfffd).contains(scalar.value) || (0x10000...0x10ffff).contains(scalar.value)
    }) else { throw CompanyTemplateEngine.Failure.invalidText }
    return text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\r", with: "&#13;")
  }
}
