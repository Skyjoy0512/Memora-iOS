import Foundation

enum MCPEventStream {
  static func isBoundary(_ data: Data) -> Bool {
    data.suffix(2) == Data([10, 10]) || data.suffix(4) == Data([13, 10, 13, 10])
  }

  static func payload(_ data: Data) -> Data? {
    let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
    let lines = text.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
    let value = lines.map { line in
      let tail = line.dropFirst(5)
      return String(tail.first == " " ? tail.dropFirst() : tail)
    }.joined(separator: "\n")
    return value.isEmpty ? nil : Data(value.utf8)
  }

  static func requestID(_ data: Data) -> Data? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let id = object["id"], !(id is NSNull) else { return nil }
    return try? JSONSerialization.data(withJSONObject: ["id": id], options: .sortedKeys)
  }
}
