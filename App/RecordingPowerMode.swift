import Foundation

enum RecordingPowerMode: String, CaseIterable, Identifiable {
  case standard, lowPower
  var id: Self { self }
  var title: String { self == .standard ? "通常" : "省電力" }
  static let settingsKey = "memora.recording.powerMode"

  static var current: Self {
    Self(rawValue: UserDefaults.standard.string(forKey: settingsKey) ?? "") ?? .standard
  }

  static func conservesResources(mode: Self, lowPower: Bool, thermalRestricted: Bool) -> Bool {
    mode == .lowPower || lowPower || thermalRestricted
  }
}
