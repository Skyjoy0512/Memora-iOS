import Foundation

/// A bounded text scanner, not a browser. It neither renders HTML nor loads its
/// styles, scripts, frames, images or linked resources.
enum WebSourceTextExtraction {
  struct Result: Sendable {
    var title: String?
    var blocks: [ProjectSourceText]
    var notice: String
    var author: String?
    var publishedAt: String?
  }

  static func read(_ data: Data, contentType: String) throws -> Result {
    guard data.count <= WebSourceHTTPDecoder.maximumBodyBytes else { throw WebSourceFailure.tooLarge }
    let fields = contentType.lowercased().components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    for field in fields.dropFirst() where field.hasPrefix("charset=") {
      let encoding = field.dropFirst(8).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
      guard ["utf-8", "utf8", "us-ascii"].contains(encoding) else { throw WebSourceFailure.unsupportedContent }
    }
    guard let string = String(data: data, encoding: .utf8) else { throw WebSourceFailure.unsupportedContent }
    try Task.checkCancellation()
    if fields.first == "text/plain" { return try result(title: nil, text: string, wasLimited: false) }
    guard fields.first == "text/html" || fields.first == "application/xhtml+xml" else { throw WebSourceFailure.unsupportedContent }
    let input = Array(data)
    var stack: [Frame] = []
    var title = Collector(maximumBytes: 1_024), body = Collector(), main = Collector(), article = Collector()
    var hiddenDepth = 0, mainDepth = 0, articleDepth = 0, titleDepth = 0
    var cursor = 0, tags = 0
    var metadata: [String: String] = [:]
    let excluded: Set<String> = ["script", "style", "template", "iframe", "noscript", "svg", "nav", "header", "footer", "aside", "form"]
    let blocks: Set<String> = ["p", "div", "section", "article", "main", "br", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "table", "blockquote"]
    let empty: Set<String> = ["br", "hr", "img", "meta", "link", "input", "source", "wbr", "area", "base", "embed", "param", "col", "track"]
    func pop(_ frame: Frame) {
      if frame.hidden { hiddenDepth -= 1 }
      if frame.name == "main" { mainDepth -= 1 }
      if frame.name == "article" { articleDepth -= 1 }
      if frame.name == "title" { titleDepth -= 1 }
    }
    func append(_ text: String) {
      guard hiddenDepth == 0 else { return }
      if titleDepth > 0 { title.append(text); return }
      body.append(text)
      if mainDepth > 0 { main.append(text) }
      if articleDepth > 0 { article.append(text) }
    }
    while cursor < input.count {
      try Task.checkCancellation()
      if input[cursor] != 60 || cursor + 1 == input.count ||
         !(input[cursor + 1] == 33 || input[cursor + 1] == 47 || input[cursor + 1] == 63 || Self.isLetter(input[cursor + 1])) {
        var end = cursor + 1
        while end < input.count, input[end] != 60 { end += 1 }
        append(entities(String(decoding: input[cursor..<end], as: UTF8.self)))
        cursor = end; continue
      }
      if input[cursor..<min(cursor + 4, input.count)].elementsEqual([60, 33, 45, 45]) {
        guard let end = find([45, 45, 62], in: input, from: cursor + 4) else { break }
        cursor = end + 3; continue
      }
      var end = cursor + 1
      var quote: UInt8?
      while end < input.count {
        let byte = input[end]
        if let current = quote { if byte == current { quote = nil } }
        else if byte == 34 || byte == 39 { quote = byte }
        else if byte == 62 { break }
        end += 1
        guard end - cursor <= 8_192 else { throw WebSourceFailure.tooLarge }
      }
      guard end < input.count else { break }
      let originalTag = String(decoding: input[cursor + 1..<end], as: UTF8.self)
      let raw = originalTag.lowercased()
      let closing = raw.hasPrefix("/")
      let name = String(raw.dropFirst(closing ? 1 : 0).prefix { $0.isASCII && ($0.isLetter || $0.isNumber) })
      cursor = end + 1
      tags += 1
      guard tags <= 30_000 else { throw WebSourceFailure.tooLarge }
      guard !name.isEmpty else { continue }
      if name == "meta", !closing {
        let attributes = attributes(in: originalTag)
        if let key = attributes["name"] ?? attributes["property"], let value = attributes["content"] {
          metadata[key.lowercased()] = entities(String(value.prefix(512)))
        }
      }
      if closing {
        if let index = stack.lastIndex(where: { $0.name == name }) {
          for frame in stack[index...] { pop(frame) }
          stack.removeSubrange(index...)
        }
        if blocks.contains(name) { append("\n") }
        continue
      }
      if name == "script" || name == "style" || name == "template" || name == "iframe" || name == "noscript" {
        guard let closeEnd = closingTag(name, in: input, from: cursor) else { break }
        cursor = closeEnd + 1; continue
      }
      if blocks.contains(name) { append("\n") }
      let hidden = excluded.contains(name) || raw.range(of: "(?:^|\\s)hidden(?:\\s|=|/|$)|aria-hidden\\s*=\\s*[\"']?true(?:[\\s\"'/]|$)", options: .regularExpression) != nil
      if !empty.contains(name), !raw.hasSuffix("/") {
        guard stack.count < 128 else { throw WebSourceFailure.tooLarge }
        stack.append(Frame(name: name, hidden: hidden))
        if hidden { hiddenDepth += 1 }
        if name == "main" { mainDepth += 1 }
        if name == "article" { articleDepth += 1 }
        if name == "title" { titleDepth += 1 }
      }
      if name == "td" || name == "th" { append(" ") }
    }
    let chosen = !article.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? article :
      (!main.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? main : body)
    var output = try result(title: title.text, text: chosen.text, wasLimited: chosen.wasLimited)
    output.author = metadata["author"] ?? metadata["article:author"]
    output.publishedAt = metadata["article:published_time"] ?? metadata["date"]
    return output
  }

  private static func attributes(in tag: String) -> [String: String] {
    guard let expression = try? NSRegularExpression(pattern: #"([a-zA-Z_:][a-zA-Z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) else { return [:] }
    var result: [String: String] = [:]
    for match in expression.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
      guard let name = Range(match.range(at: 1), in: tag) else { continue }
      let value = Range(match.range(at: 2), in: tag) ?? Range(match.range(at: 3), in: tag)
      if let value { result[String(tag[name]).lowercased()] = String(tag[value]) }
    }
    return result
  }

  private static func result(title: String?, text: String, wasLimited: Bool) throws -> Result {
    let lines = text.components(separatedBy: .newlines).map {
      $0.split(whereSeparator: { $0.isWhitespace || $0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }).joined(separator: " ")
    }.filter { !$0.isEmpty }
    let bounded = String(lines.prefix(2_000).joined(separator: "\n").prefix(80_000))
    var collector = Collector()
    collector.append(bounded)
    guard !collector.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WebSourceFailure.noText }
    let limited = wasLimited || collector.wasLimited || lines.count > 2_000 || bounded.count < lines.joined(separator: "\n").count
    let safeTitle = title?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return Result(title: safeTitle.flatMap { $0.isEmpty ? nil : String($0.prefix(256)) },
      blocks: [ProjectSourceText(text: collector.text)],
      notice: "Webページの文字を取得しました。画像・動画・JavaScriptで表示される内容は解析していません。" +
        (limited ? " 本文は先頭80,000文字・256KB以内の抜粋です。" : ""))
  }

  private static func find(_ pattern: [UInt8], in bytes: [UInt8], from start: Int, ignoringCase: Bool = false) -> Int? {
    guard pattern.count <= bytes.count - start else { return nil }
    for index in start...(bytes.count - pattern.count) {
      if pattern.indices.allSatisfy({ offset in
        let value = bytes[index + offset]
        return (ignoringCase && (65...90).contains(value) ? value + 32 : value) == pattern[offset]
      }) { return index }
    }
    return nil
  }

  private static func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }

  private static func closingTag(_ name: String, in bytes: [UInt8], from start: Int) -> Int? {
    let pattern = Array("</\(name)".utf8)
    var cursor = start
    while let found = find(pattern, in: bytes, from: cursor, ignoringCase: true) {
      let after = found + pattern.count
      guard after < bytes.count else { return nil }
      if [9, 10, 13, 32, 47, 62].contains(bytes[after]) { return bytes[after...].firstIndex(of: 62) }
      cursor = after
    }
    return nil
  }

  private static func entities(_ text: String) -> String {
    let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "reg": "®", "bull": "•", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”"]
    var result = "", cursor = text.startIndex
    while cursor < text.endIndex {
      if text[cursor] == "&", let end = text[cursor...].prefix(34).firstIndex(of: ";") {
        let token = String(text[text.index(after: cursor)..<end])
        var replacement = named[token]
        if token.hasPrefix("#") {
          let hex = token.lowercased().hasPrefix("#x")
          if let number = UInt32(token.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) {
            replacement = CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
          }
        }
        if let replacement { result += replacement; cursor = text.index(after: end); continue }
      }
      result.append(text[cursor]); cursor = text.index(after: cursor)
    }
    return result
  }

  private struct Frame { var name: String; var hidden: Bool }

  private struct Collector {
    var maximumBytes = 256 * 1024
    var text = ""
    var count = 0
    var wasLimited = false
    mutating func append(_ value: String) {
      let available = maximumBytes - count
      guard available > 0 else { wasLimited = true; return }
      if value.utf8.count <= available { text += value; count += value.utf8.count; return }
      var bytes = Data(value.utf8.prefix(available))
      while !bytes.isEmpty, String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
      text += String(data: bytes, encoding: .utf8) ?? ""
      count = maximumBytes; wasLimited = true
    }
  }
}
