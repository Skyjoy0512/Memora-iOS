import Foundation
import Security
import CoreFoundation

/// The account details an OpenAI ID token proves.
struct ChatGPTIdentity: Hashable, Sendable {
  /// The stable subject identifier of the account.
  var subject: String
  /// The account's email address, when the token carries one.
  var email: String?
  /// The account's display name, when the token carries one.
  var name: String?
}

/// Why an ID token could not be trusted.
enum ChatGPTIDTokenError: LocalizedError, Equatable {
  /// The token was malformed, or its claims did not match the request.
  case invalidToken
  /// The signing keys could not be fetched. The token was not checked.
  case verificationUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidToken:
      return "ChatGPTの本人確認を確認できませんでした。もう一度サインインしてください。"
    case .verificationUnavailable:
      return "ChatGPTの署名鍵を確認できませんでした。接続は保持しています。少ししてからもう一度お試しください。"
    }
  }
}

/// Checks a ChatGPT ID token against OpenAI's published signing keys. Only the
/// public JWKS is used, so a token cannot be edited without its signature
/// failing verification.
actor ChatGPTIDTokenVerifier {
  typealias Identity = ChatGPTIdentity

  static let issuer = "https://auth.openai.com"
  static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
  static let clockTolerance: TimeInterval = 5

  private struct RSAPublicKey: Equatable {
    var modulus: String
    var exponent: String
  }

  private var cachedJWKSData: Data?
  private var cachedKeys: [String: RSAPublicKey] = [:]

  func reset() {
    cachedJWKSData = nil
    cachedKeys = [:]
  }

  func verify(idToken: String, audience: String, nonce: String? = nil) async throws -> Identity {
    let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3,
          !segments[0].isEmpty,
          !segments[1].isEmpty,
          !segments[2].isEmpty,
          let headerData = Self.base64URLData(String(segments[0])),
          let payloadData = Self.base64URLData(String(segments[1])),
          let signature = Self.base64URLData(String(segments[2])),
          let header = Self.jsonObject(headerData),
          header["alg"] as? String == "RS256",
          let keyID = header["kid"] as? String,
          !keyID.isEmpty,
          let claims = Self.jsonObject(payloadData) else {
      throw ChatGPTIDTokenError.invalidToken
    }

    guard claims["iss"] as? String == Self.issuer,
          Self.audienceContains(claims["aud"], audience: audience),
          let expiration = Self.number(claims["exp"]),
          let issuedAt = Self.number(claims["iat"]),
          let subject = Self.nonEmptyString(claims["sub"]),
          !subject.isEmpty else {
      throw ChatGPTIDTokenError.invalidToken
    }

    let now = Date().timeIntervalSince1970
    guard now <= expiration + Self.clockTolerance,
          issuedAt <= now + Self.clockTolerance else {
      throw ChatGPTIDTokenError.invalidToken
    }

    if let nonce, claims["nonce"] as? String != nonce {
      throw ChatGPTIDTokenError.invalidToken
    }

    let key = try await signingKey(for: keyID)
    guard let modulus = Self.base64URLData(key.modulus),
          let exponent = Self.base64URLData(key.exponent),
          let publicKey = Self.makePublicKey(modulus: modulus, exponent: exponent),
          let signingInput = "\(segments[0]).\(segments[1])".data(using: .utf8),
          SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData,
            signature as CFData,
            nil
          ) else {
      throw ChatGPTIDTokenError.invalidToken
    }

    return Identity(
      subject: subject,
      email: Self.nonEmptyString(claims["email"]),
      name: Self.nonEmptyString(claims["name"])
    )
  }

  private func signingKey(for keyID: String) async throws -> RSAPublicKey {
    if let key = cachedKeys[keyID] {
      return key
    }

    if cachedJWKSData == nil {
      cachedJWKSData = try await fetchJWKSData()
      cachedKeys = try Self.keys(from: cachedJWKSData ?? Data())
    }

    guard let key = cachedKeys[keyID] else {
      throw ChatGPTIDTokenError.invalidToken
    }
    return key
  }

  private func fetchJWKSData() async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(from: Self.jwksURL)
    } catch {
      throw ChatGPTIDTokenError.verificationUnavailable
    }

    guard let httpResponse = response as? HTTPURLResponse,
          (200..<300).contains(httpResponse.statusCode) else {
      throw ChatGPTIDTokenError.verificationUnavailable
    }

    cachedJWKSData = data
    return data
  }

  private static func keys(from data: Data) throws -> [String: RSAPublicKey] {
    guard let object = jsonObject(data),
          let records = object["keys"] as? [Any] else {
      throw ChatGPTIDTokenError.verificationUnavailable
    }

    var keys: [String: RSAPublicKey] = [:]
    for case let record as [String: Any] in records {
      let keyType = record["kty"] as? String
      guard let keyID = record["kid"] as? String,
            !keyID.isEmpty,
            keyType == nil || keyType == "RSA",
            let modulus = record["n"] as? String,
            !modulus.isEmpty,
            let exponent = record["e"] as? String,
            !exponent.isEmpty else {
        continue
      }
      keys[keyID] = RSAPublicKey(modulus: modulus, exponent: exponent)
    }
    return keys
  }

  private static func jsonObject(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func audienceContains(_ value: Any?, audience: String) -> Bool {
    if let single = value as? String {
      return single == audience
    }
    if let multiple = value as? [Any] {
      return multiple.contains { ($0 as? String) == audience }
    }
    return false
  }

  private static func number(_ value: Any?) -> Double? {
    guard let value,
          let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let result = number.doubleValue
    return result.isFinite ? result : nil
  }

  private static func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else {
      return nil
    }
    return string
  }

  private static func base64URLData(_ string: String) -> Data? {
    guard !string.isEmpty,
          string.utf8.allSatisfy({ byte in
            (byte >= 65 && byte <= 90)
              || (byte >= 97 && byte <= 122)
              || (byte >= 48 && byte <= 57)
              || byte == 45
              || byte == 95
          }) else {
      return nil
    }

    var base64 = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    guard remainder != 1 else { return nil }
    if remainder != 0 {
      base64.append(String(repeating: "=", count: 4 - remainder))
    }
    return Data(base64Encoded: base64)
  }

  private static func makePublicKey(modulus: Data, exponent: Data) -> SecKey? {
    let pkcs1 = derSequence([
      derInteger(modulus),
      derInteger(exponent)
    ])
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass: kSecAttrKeyClassPublic,
      kSecAttrKeySizeInBits: NSNumber(value: modulus.count * 8)
    ]
    var error: Unmanaged<CFError>?
    return SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error)
  }

  private static func derSequence(_ items: [Data]) -> Data {
    let content = items.reduce(into: Data()) { $0.append($1) }
    return Data([0x30]) + derLength(content.count) + content
  }

  private static func derInteger(_ bytes: Data) -> Data {
    var value = bytes
    while value.count > 1, value.first == 0 {
      value = Data(value.dropFirst())
    }
    if value.isEmpty {
      value = Data([0])
    }
    if let first = value.first, first & 0x80 != 0 {
      value.insert(0, at: 0)
    }
    return Data([0x02]) + derLength(value.count) + value
  }

  private static func derLength(_ length: Int) -> Data {
    if length < 0x80 {
      return Data([UInt8(length)])
    }

    var remaining = length
    var bytes: [UInt8] = []
    while remaining > 0 {
      bytes.insert(UInt8(remaining & 0xFF), at: 0)
      remaining >>= 8
    }
    return Data([0x80 | UInt8(bytes.count)] + bytes)
  }
}
