import Foundation

/// Inserts validated fragments without serializing an existing part's styles or extensions.
struct OfficeXMLInsertion {
  var document: OfficeXMLDocument
  private var source: NSString
  private var opening: [Int: NSRange] = [:]
  private var closing: [Int: NSRange] = [:]
  private var names: [Int: String] = [:]
  private static let tokens = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|</?[A-Za-z_][A-Za-z0-9_.:-]*(?:[^\"'<>]|\"[^\"]*\"|'[^']*')*>"#)

  init(_ data: Data) throws {
    document = try OfficeXMLDocument(data: data)
    let text = String(decoding: data, as: UTF8.self)
    source = text as NSString
    var stack: [(Int, String)] = [], next = 0
    for token in Self.tokens.matches(in: text, range: NSRange(location: 0, length: source.length)) {
      try Task.checkCancellation()
      let raw = source.substring(with: token.range)
      if raw.hasPrefix("<!--") || raw.hasPrefix("<?") || raw.hasPrefix("<![CDATA[") { continue }
      let isClosing = raw.hasPrefix("</")
      let name = String(raw.dropFirst(isClosing ? 2 : 1).prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" })
      if isClosing {
        guard let last = stack.popLast(), last.1 == name else { throw OfficeArchiveReader.Failure.invalid }
        closing[last.0] = token.range
      } else {
        guard next < document.nodes.count, document.nodes[next].name == name.split(separator: ":").last.map(String.init) else { throw OfficeArchiveReader.Failure.invalid }
        opening[next] = token.range; names[next] = name
        if !raw.hasSuffix("/>") { stack.append((next, name)) }
        next += 1
      }
    }
    guard next == document.nodes.count, stack.isEmpty else { throw OfficeArchiveReader.Failure.invalid }
  }

  func inserting(_ fragment: String, into index: Int) throws -> Data {
    guard let start = opening[index], let name = names[index] else { throw OfficeArchiveReader.Failure.invalid }
    let result = NSMutableString(string: source as String)
    if let end = closing[index] { result.insert(fragment, at: end.location) }
    else {
      let original = source.substring(with: start)
      guard original.hasSuffix("/>") else { throw OfficeArchiveReader.Failure.invalid }
      result.replaceCharacters(in: start, with: original.dropLast(2) + ">" + fragment + "</" + name + ">")
    }
    let bytes = Data((result as String).utf8)
    _ = try OfficeXMLDocument(data: bytes)
    return bytes
  }

  func inserting(_ fragment: String, before index: Int) throws -> Data {
    guard let start = opening[index] else { throw OfficeArchiveReader.Failure.invalid }
    let result = NSMutableString(string: source as String); result.insert(fragment, at: start.location)
    let bytes = Data((result as String).utf8); _ = try OfficeXMLDocument(data: bytes)
    return bytes
  }

  func replacingLeafText(_ text: String, at index: Int) throws -> Data {
    guard document.nodes.indices.contains(index), document.nodes[index].children.isEmpty,
          let start = opening[index], let end = closing[index] else { throw OfficeArchiveReader.Failure.invalid }
    let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    let result = NSMutableString(string: source as String)
    result.replaceCharacters(in: NSRange(location: NSMaxRange(start), length: end.location - NSMaxRange(start)), with: escaped)
    let bytes = Data((result as String).utf8); _ = try OfficeXMLDocument(data: bytes)
    return bytes
  }
}
