import Foundation

enum MeetingSource: String, Hashable, Codable {
  case recording
  case importFile

  var label: String {
    switch self {
    case .recording:
      "録音"
    case .importFile:
      "インポート"
    }
  }
}

extension MeetingSource {
  /// A kind this build does not know — a record saved as a phone call while
  /// that feature existed, say — reads as an import, so one record can never
  /// make the whole library unreadable.
  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = MeetingSource(rawValue: raw) ?? .importFile
  }
}
