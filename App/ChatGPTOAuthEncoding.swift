import CryptoKit
import Foundation

/// The byte level encoding the ChatGPT authorization requests need: random
/// values, the PKCE challenge and the form encoded request body.
enum ChatGPTOAuthEncoding {
  /// A fresh random value of 32 bytes, base64url encoded without padding.
  static func randomValue() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return base64URL(Data(bytes))
  }

  /// The PKCE challenge for a verifier: the base64url encoded SHA-256 digest
  /// of the verifier's ASCII bytes.
  static func challenge(for verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
  }

  /// A form encoded request body. Every byte outside the unreserved set is
  /// percent encoded.
  static func form(_ values: [String: String]) -> Data {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let text = values.keys.sorted().map { key in
      key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + values[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!
    }.joined(separator: "&")
    return Data(text.utf8)
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
