import SwiftUI

enum CaptureAction: CaseIterable, Identifiable {
  case recording
  case importAudio
  case onlineMeeting
  case project

  var id: Self { self }

  var title: String {
    switch self {
    case .recording: "録音を開始"
    case .importAudio: "音声を取り込む"
    case .onlineMeeting: "オンライン会議"
    case .project: "プロジェクトを作成"
    }
  }

  var symbol: String {
    switch self {
    case .recording: "waveform"
    case .importAudio: "square.and.arrow.down"
    case .onlineMeeting: "video"
    case .project: "folder.badge.plus"
    }
  }
}

struct OnlineMeetingCaptureView: View {
  var beginRecording: () -> Void

  var body: some View {
    List {
      Section {
        Label("Zoom", systemImage: "video")
        Label("Google Meet", systemImage: "video")
        Label("Microsoft Teams", systemImage: "video")
      } header: {
        Text("対応する会議")
      } footer: {
        Text("会議をスピーカーで再生し、Memoraをバックグラウンドで録音します。開始前に参加者へ録音を知らせてください。")
      }

      Section {
        Button("録音の準備をする", systemImage: "waveform", action: beginRecording)
      }
    }
    .navigationTitle("オンライン会議")
    .navigationBarTitleDisplayMode(.inline)
  }
}
