import Foundation

// Plans, company licenses and Memora Intelligence credits. What a plan allows
// is decided here, so every screen and request reads the same answer.
extension MemoraModel {
  private static let licenseAccount = "memora.license.code"

  /// The license, while it has not expired.
  var activeLicense: MemoraLicense? {
    guard let license, !license.isExpired else { return nil }
    return license
  }

  /// The plan in force: a company license outranks a personal plan.
  var effectivePlan: MemoraPlan? {
    activeLicense?.plan ?? plan
  }

  var planName: String {
    if let license = activeLicense { return "\(license.plan.label)（\(license.company)）" }
    return plan?.label ?? "無料"
  }

  /// Why Memora Intelligence cannot be used now, or nil when it can.
  var memoraIntelligenceBlocker: String? {
    guard effectivePlan != nil else {
      return "Memora Intelligenceはライト以上のプランで使えます。自分のAPIキー（BYOK）や端末内AIは無料で使えます。"
    }
    guard MemoraIntelligence.isConfigured else {
      return "Memora Intelligenceのサーバーはまだ接続されていません。接続されるまでは、端末内AIか自分のAPIキーを使ってください。"
    }
    return nil
  }

  // MARK: - Licenses

  /// Checks a code and, when it is valid, makes it the active license. The
  /// code itself is kept in the keychain and checked again on every launch.
  @discardableResult
  func activateLicense(code: String) throws -> MemoraLicense {
    let license = try LicenseCodeVerifier.license(from: code)
    guard KeychainStore.set(code.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.licenseAccount) else {
      throw LicenseCodeError.storage
    }
    self.license = license
    isSubscribed = true
    UserDefaults.standard.set(true, forKey: StorageKey.isSubscribed)
    return license
  }

  func removeLicense() throws {
    guard KeychainStore.set(nil, forKey: Self.licenseAccount) else { throw LicenseCodeError.storage }
    license = nil
    choosePlan(plan)
  }

  /// The stored code, verified again; an edited or expired code is dropped.
  static func storedLicense() -> MemoraLicense? {
    guard let code = KeychainStore.string(forKey: licenseAccount) else { return nil }
    return try? LicenseCodeVerifier.license(from: code)
  }
}
