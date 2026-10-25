import Foundation

@main
enum LicensePersistenceChecks {
  static func main() throws {
    let model = MemoraModel()
    KeychainStore.succeeds = false
    do { try model.activateLicense(code: "A"); preconditionFailure("Failed Keychain write activated license") }
    catch LicenseCodeError.storage {}
    precondition(model.license == nil && !model.isSubscribed && UserDefaults.standard.values.isEmpty)
    KeychainStore.succeeds = true
    try model.activateLicense(code: " A \n")
    let original = model.license
    precondition(model.activeLicense?.id == "A" && MemoraModel.storedLicense() == original)
    precondition(KeychainStore.code == "A" && UserDefaults.standard.values["subscribed"] == true)

    KeychainStore.succeeds = false
    do { try model.activateLicense(code: "B"); preconditionFailure("Failed replacement activated license") }
    catch LicenseCodeError.storage {}
    precondition(model.license == original && model.isSubscribed && MemoraModel.storedLicense() == original)
    do { try model.removeLicense(); preconditionFailure("Failed deletion cleared license") }
    catch LicenseCodeError.storage {}
    precondition(model.license == original && model.isSubscribed && KeychainStore.code == "A")
    precondition(UserDefaults.standard.values["subscribed"] == true)

    KeychainStore.succeeds = true
    do { try model.activateLicense(code: "expired"); preconditionFailure("Expired license activated") }
    catch LicenseCodeError.expired {}
    precondition(model.license == original && KeychainStore.code == "A")
    try model.removeLicense()
    precondition(model.license == nil && !model.isSubscribed && MemoraModel.storedLicense() == nil)
    precondition(UserDefaults.standard.values["subscribed"] == false)

    model.plan = .pro
    try model.activateLicense(code: "B")
    try model.removeLicense()
    precondition(model.effectivePlan == .pro && model.isSubscribed)
    KeychainStore.code = "expired"
    precondition(MemoraModel.storedLicense() == nil && KeychainStore.code == "expired", "Invalid stored codes must not be destroyed")
    model.license = MemoraLicense(id: "old", company: "Fixture", plan: .team, seats: 1, expiresAt: .distantPast)
    precondition(model.activeLicense == nil && model.effectivePlan == .pro)
    print("LicensePersistenceChecks: PASS; production activation/removal, failed write/delete, replacement, reload, expiry, personal-plan fallback. Keychain and verifier are isolated fixtures; no billing or real credentials.")
  }
}

final class MemoraModel {
  var license: MemoraLicense?
  var plan: MemoraPlan?
  var isSubscribed = false
  enum StorageKey { static let isSubscribed = "subscribed" }
  func choosePlan(_ plan: MemoraPlan?) {
    self.plan = plan
    isSubscribed = plan != nil || activeLicense != nil
    UserDefaults.standard.set(isSubscribed, forKey: StorageKey.isSubscribed)
  }
}

enum KeychainStore {
  static var succeeds = true
  static var code: String?
  static func set(_ value: String?, forKey: String) -> Bool {
    guard succeeds else { return false }
    code = value
    return true
  }
  static func string(forKey: String) -> String? { code }
}

enum UserDefaults {
  static var standard = FixtureDefaults()
  struct FixtureDefaults {
    var values: [String: Bool] = [:]
    mutating func set(_ value: Bool, forKey key: String) { values[key] = value }
  }
}

enum LicenseCodeVerifier {
  static func license(from code: String) throws -> MemoraLicense {
    let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard code != "expired" else { throw LicenseCodeError.expired }
    return MemoraLicense(id: code, company: "Fixture", plan: .team, seats: 1, expiresAt: .distantFuture)
  }
}
enum MemoraIntelligence { static let isConfigured = false }
