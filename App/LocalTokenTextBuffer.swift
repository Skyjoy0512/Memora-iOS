import Foundation

/// Token boundaries may split a Japanese UTF-8 character into several pieces.
struct LocalTokenTextBuffer {
  private var pending: [UInt8] = []

  mutating func append(_ bytes: [UInt8]) throws -> String {
    pending.append(contentsOf: bytes)
    if let text = String(bytes: pending, encoding: .utf8) {
      pending.removeAll(keepingCapacity: true)
      return text
    }
    guard pending.count <= 1_024 else { throw LiveVoiceError.unavailable("モデルの出力を読み取れませんでした。") }
    return ""
  }

  func finish() throws {
    guard pending.isEmpty else { throw LiveVoiceError.unavailable("モデルの出力が途中で終了しました。") }
  }
}
