import Foundation

/// HTTP/1.1 only. It never follows a redirect, decompresses a response or reads
/// cookies. The caller closes the connection as soon as a bounded reply exists.
struct WebSourceHTTPDecoder {
  static let maximumBodyBytes = 2 * 1024 * 1024
  private var buffer = Data()
  private var cursor = 0
  private var body = Data()
  private var head: Response?
  private var length: Int?
  private var chunked = false
  private var chunkLength: Int?
  private var chunkCount = 0
  private static let newline = Data([13, 10])

  struct Response: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data
  }

  mutating func append(_ data: Data, ended: Bool) throws -> Response? {
    guard buffer.count + data.count <= Self.maximumBodyBytes + 64 * 1024 else { throw WebSourceFailure.tooLarge }
    buffer.append(data)
    if head == nil {
      guard let separator = buffer.range(of: Data([13, 10, 13, 10])) else {
        guard buffer.count <= 32 * 1024 else { throw WebSourceFailure.tooLarge }
        if ended { throw WebSourceFailure.invalidResponse }
        return nil
      }
      guard separator.lowerBound <= 32 * 1024,
            let text = String(data: buffer.prefix(separator.lowerBound), encoding: .ascii) else { throw WebSourceFailure.invalidResponse }
      let lines = text.components(separatedBy: "\r\n")
      let statusLine = (lines.first ?? "").split(separator: " ", maxSplits: 2)
      guard statusLine.count >= 2, ["HTTP/1.1", "HTTP/1.0"].contains(String(statusLine[0])),
            let status = Int(statusLine[1]), (200...599).contains(status), lines.count <= 200 else { throw WebSourceFailure.invalidResponse }
      var headers: [String: String] = [:]
      for line in lines.dropFirst() {
        guard let colon = line.firstIndex(of: ":") else { throw WebSourceFailure.invalidResponse }
        let name = String(line[..<colon]).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
              value.utf8.allSatisfy({ $0 == 9 || (32...126).contains($0) }) else { throw WebSourceFailure.invalidResponse }
        if ["content-type", "content-length", "transfer-encoding", "content-encoding", "location"].contains(name) {
          guard headers[name] == nil else { throw WebSourceFailure.invalidResponse }
          headers[name] = value
        }
      }
      head = Response(status: status, headers: headers, body: Data())
      cursor = separator.upperBound
      if status != 200 { return head }
      guard let type = headers["content-type"]?.lowercased(),
            ["text/html", "application/xhtml+xml", "text/plain"].contains(type.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)),
            headers["content-encoding"].map({ $0.lowercased() == "identity" }) ?? true else { throw WebSourceFailure.unsupportedContent }
      if let transfer = headers["transfer-encoding"] {
        guard transfer.lowercased() == "chunked", headers["content-length"] == nil else { throw WebSourceFailure.invalidResponse }
        chunked = true
      } else if let value = headers["content-length"] {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(value) else { throw WebSourceFailure.invalidResponse }
        guard count <= Self.maximumBodyBytes else { throw WebSourceFailure.tooLarge }
        length = count
      }
    }
    if chunked {
      while true {
        try Task.checkCancellation()
        if chunkLength == nil {
          guard let end = buffer.range(of: Self.newline, in: cursor..<buffer.count) else {
            guard buffer.count - cursor <= 128 else { throw WebSourceFailure.invalidResponse }
            break
          }
          guard end.lowerBound - cursor <= 128, let raw = String(data: buffer[cursor..<end.lowerBound], encoding: .ascii),
                raw.utf8.allSatisfy({ $0 == 9 || (32...126).contains($0) }) else { throw WebSourceFailure.invalidResponse }
          let size = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
          guard !size.isEmpty, size.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                let count = Int(size, radix: 16) else { throw WebSourceFailure.invalidResponse }
          guard count <= Self.maximumBodyBytes - body.count else { throw WebSourceFailure.tooLarge }
          chunkCount += 1
          guard chunkCount <= 8_192 else { throw WebSourceFailure.tooLarge }
          chunkLength = count; cursor = end.upperBound
        }
        guard let size = chunkLength, buffer.count - cursor >= size + 2 else { break }
        guard buffer[cursor + size..<cursor + size + 2] == Self.newline else { throw WebSourceFailure.invalidResponse }
        body.append(buffer[cursor..<cursor + size]); cursor += size + 2
        if size == 0 {
          guard cursor == buffer.count else { throw WebSourceFailure.invalidResponse }
          return response(body)
        }
        chunkLength = nil
      }
      if ended { throw WebSourceFailure.invalidResponse }
      return nil
    }
    let count = buffer.count - cursor
    guard count <= Self.maximumBodyBytes, length.map({ count <= $0 }) ?? true else { throw WebSourceFailure.tooLarge }
    if let length, count == length { return response(buffer.subdata(in: cursor..<buffer.count)) }
    if ended {
      guard length == nil else { throw WebSourceFailure.invalidResponse }
      return response(buffer.subdata(in: cursor..<buffer.count))
    }
    return nil
  }

  private func response(_ body: Data) -> Response? {
    guard var response = head else { return nil }
    response.body = body
    return response
  }
}
