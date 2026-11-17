import CryptoKit
import Foundation

/// Presentation state has no tool grants and is never sent as model context.
struct JSONRenderSnapshot: Codable, Hashable, Sendable {
  var fingerprint: String
  var specJSON: String
  var stateJSON: String
  var text: String

  static func make(body: [String: Any], fingerprint: String) -> Self? {
    guard let spec = body["spec"] as? [String: Any], let state = body["state"] as? [String: Any],
          let specData = try? JSONSerialization.data(withJSONObject: spec, options: [.sortedKeys]),
          let stateData = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
          let specJSON = String(data: specData, encoding: .utf8), let stateJSON = String(data: stateData, encoding: .utf8),
          let text = body["text"] as? String else { return nil }
    let snapshot = Self(fingerprint: fingerprint, specJSON: specJSON, stateJSON: stateJSON, text: text)
    return snapshot.isValid ? snapshot : nil
  }

  static func fingerprint(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  var maximumEncodedBytes: Int { (fingerprint.utf8.count + specJSON.utf8.count + stateJSON.utf8.count + text.utf8.count) * 6 + 256 }

  var isValid: Bool {
    guard fingerprint.count == 64, fingerprint.allSatisfy(\.isHexDigit),
          specJSON.utf8.count <= 256 * 1_024, stateJSON.utf8.count <= 64 * 1_024,
          text.utf8.count <= 128 * 1_024,
          let spec = specJSON.data(using: .utf8), let state = stateJSON.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: spec) as? [String: Any],
          object["root"] is String, let elements = object["elements"] as? [String: Any],
          elements.count <= 256,
          (try? JSONSerialization.jsonObject(with: state)) is [String: Any] else { return false }
    return true
  }
}
