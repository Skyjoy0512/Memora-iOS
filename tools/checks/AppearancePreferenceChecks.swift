import Foundation

@main struct AppearancePreferenceChecks {
  static func main() {
    let name = "MemoraAppearanceChecks.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    precondition(AppearancePreference.migrate(defaults: defaults) == .system)
    defaults.removeObject(forKey: "memora.appearance")
    defaults.set(false, forKey: "memora.prefersDarkAppearance")
    precondition(AppearancePreference.migrate(defaults: defaults) == .system)
    defaults.removeObject(forKey: "memora.appearance")
    defaults.set(true, forKey: "memora.prefersDarkAppearance")
    precondition(AppearancePreference.migrate(defaults: defaults) == .dark)
    defaults.set("light", forKey: "memora.appearance")
    precondition(AppearancePreference.migrate(defaults: defaults) == .light)
    defaults.set("system", forKey: "memora.appearance")
    precondition(AppearancePreference.migrate(defaults: defaults) == .system)
    print("AppearancePreferenceChecks passed: old off follows system, old on stays dark, explicit light/system survives migration")
  }
}
