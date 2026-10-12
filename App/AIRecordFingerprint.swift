import CryptoKit
import Foundation

enum AIRecordFingerprint {
  static func make<Value: Encodable>(_ value: Value) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
