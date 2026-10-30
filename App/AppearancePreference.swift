import Foundation

// The old switch's off state followed the device; it never meant forced light.
enum AppearancePreference: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: Self { self }
  var label: String {
    switch self { case .system: "システムに合わせる"; case .light: "ライト"; case .dark: "ダーク" }
  }
  static func migrate(defaults: UserDefaults = .standard) -> Self {
    if let raw = defaults.string(forKey: "memora.appearance"), let saved = Self(rawValue: raw) { return saved }
    let restored: Self = defaults.bool(forKey: "memora.prefersDarkAppearance") ? .dark : .system
    defaults.set(restored.rawValue, forKey: "memora.appearance")
    return restored
  }
}
