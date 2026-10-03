import CryptoKit
import Foundation

/// Checks a license code offline: `MEMORA-<payload>.<signature>`, the payload
/// signed with the issuer's Ed25519 key. Only the public key is in the app, so a
/// code cannot be forged or edited without the issuer's private key.
enum LicenseCodeVerifier {
  static func license(from code: String) throws -> MemoraLicense {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("MEMORA-") else { throw LicenseCodeError.malformed }
    let parts = trimmed.dropFirst("MEMORA-".count).split(separator: ".")
    guard parts.count == 2,
          let payload = Data(base64URL: String(parts[0])),
          let signature = Data(base64URL: String(parts[1])) else {
      throw LicenseCodeError.malformed
    }
    guard let keyText = Bundle.main.object(forInfoDictionaryKey: "MemoraLicensePublicKey") as? String,
          let keyData = Data(base64Encoded: keyText),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
      throw LicenseCodeError.verifierMissing
    }
    guard publicKey.isValidSignature(signature, for: payload) else {
      throw LicenseCodeError.invalidSignature
    }

    guard let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let id = json["id"] as? String,
          let company = json["company"] as? String,
          let plan = (json["plan"] as? String).flatMap(MemoraPlan.init(rawValue:)),
          let expires = (json["expiresAt"] as? NSNumber)?.doubleValue else {
      throw LicenseCodeError.malformed
    }
    let license = MemoraLicense(
      id: id,
      company: company,
      plan: plan,
      seats: (json["seats"] as? Int) ?? 1,
      expiresAt: Date(timeIntervalSince1970: expires)
    )
    guard !license.isExpired else { throw LicenseCodeError.expired }
    return license
  }
}

private extension Data {
  init?(base64URL string: String) {
    var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    self.init(base64Encoded: base64)
  }
}
