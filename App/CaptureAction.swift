import SwiftUI

enum CaptureAction: CaseIterable, Identifiable {
  case recording
  case importAudio
  case onlineMeeting

  var id: Self { self }

  var title: String {
    switch self {
    case .recording: "録音を開始"
    case .importAudio: "音声を取り込む"
    case .onlineMeeting: "オンライン会議"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .recording: .waveform
    case .importAudio: .squareAndArrowDown
    case .onlineMeeting: .video
    }
  }
}
