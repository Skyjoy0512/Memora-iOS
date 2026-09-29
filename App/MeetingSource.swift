import Foundation

enum MeetingSource: String, Hashable, Codable {
  case recording
  case importFile
  /// A phone call brought in from iPhone's own call recording.
  case phoneCall

  var label: String {
    switch self {
    case .recording:
      "録音"
    case .importFile:
      "インポート"
    case .phoneCall:
      "通話"
    }
  }

  /// The badge a record of this kind shows in lists.
  var symbol: MemoraIcon {
    switch self {
    case .recording: .waveform
    case .importFile: .squareAndArrowDown
    case .phoneCall: .phone
    }
  }
}
