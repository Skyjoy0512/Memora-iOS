import SwiftUI

enum CaptureAction: CaseIterable, Identifiable {
  case recording
  case importAudio
  case onlineMeeting
  case lifeLog
  case project

  var id: Self { self }

  var title: String {
    switch self {
    case .recording: "録音を開始"
    case .importAudio: "音声を取り込む"
    case .onlineMeeting: "オンライン会議"
    case .lifeLog: "メモ・写真・場所を記録"
    case .project: "プロジェクトを作成"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .recording: .waveform
    case .importAudio: .squareAndArrowDown
    case .onlineMeeting: .video
    case .lifeLog: .squareAndPencil
    case .project: .folderBadgePlus
    }
  }
}
