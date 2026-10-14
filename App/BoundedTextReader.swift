import Foundation

enum BoundedTextReader {
  struct Result: Sendable {
    var text: String
    var wasTruncated: Bool
  }

  enum Failure: Error { case invalidFile, invalidUTF8 }

  static func read(_ url: URL, maximumBytes: Int) throws -> Result {
    guard url.isFileURL, maximumBytes > 0, maximumBytes <= 512 * 1024 else { throw Failure.invalidFile }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalidFile }
    try Task.checkCancellation()
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    // The extra byte distinguishes a cut UTF-8 sequence from a malformed file ending.
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    try Task.checkCancellation()
    let truncated = data.count > maximumBytes
    guard let text = decodeUTF8(Data(data.prefix(maximumBytes)), allowingIncompleteTail: truncated) else {
      throw Failure.invalidUTF8
    }
    return Result(text: text, wasTruncated: truncated)
  }

  static func decodeUTF8(_ data: Data, allowingIncompleteTail: Bool = false) -> String? {
    if let text = String(data: data, encoding: .utf8) { return text }
    guard allowingIncompleteTail else { return nil }
    for dropped in 1...3 where data.count >= dropped {
      let tail = Array(data.suffix(dropped))
      let first = tail[0]
      let length: Int
      switch first {
      case 0xC2...0xDF: length = 2
      case 0xE0...0xEF: length = 3
      case 0xF0...0xF4: length = 4
      default: continue
      }
      guard tail.count < length, tail.dropFirst().allSatisfy({ (0x80...0xBF).contains($0) }) else { continue }
      if tail.count > 1 {
        guard !(first == 0xE0 && tail[1] < 0xA0), !(first == 0xED && tail[1] > 0x9F),
              !(first == 0xF0 && tail[1] < 0x90), !(first == 0xF4 && tail[1] > 0x8F) else { continue }
      }
      if let text = String(data: data.dropLast(dropped), encoding: .utf8) { return text }
    }
    return nil
  }
}
