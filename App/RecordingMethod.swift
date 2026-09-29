import Foundation

/// How a calendar event is recorded: from the room's microphone, or through
/// the web meeting preparation.
enum RecordingMethod: CaseIterable, Identifiable {
  case inPerson
  case online

  var id: Self { self }

  var title: String {
    switch self {
    case .inPerson: "対面で録音"
    case .online: "Web会議として録音"
    }
  }

  var detail: String {
    switch self {
    case .inPerson: "この端末のマイクですぐに録音を始めます"
    case .online: "Zoom・Meet・Teamsなどの音声を録音する準備をします"
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .inPerson: .person2
    case .online: .video
    }
  }
}
