import Foundation

/// How a journal entry came to exist. Only `.manual` entries are made by hand;
/// the rest are placed by the app and shown with an "自動" mark.
enum LifeLogOrigin: String, Hashable, Codable {
  case manual
  case stationPass
  case visit
  case calendar
}
