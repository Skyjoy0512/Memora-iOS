import SwiftUI

struct OnlineMeetingCaptureView: View {
  var beginRecording: () -> Void

  var body: some View {
    MemoraList {
      Section {
        Label("Zoom", icon: .video)
        Label("Google Meet", icon: .video)
        Label("Microsoft Teams", icon: .video)
      } header: {
        Text("対応する会議")
      } footer: {
        Text("会議をスピーカーで再生し、Memoraをバックグラウンドで録音します。開始前に参加者へ録音を知らせてください。")
      }

      Section {
        Button("録音の準備をする", icon: .waveform, action: beginRecording)
      }
    }
    .navigationTitle("オンライン会議")
    .navigationBarTitleDisplayMode(.inline)
  }
}
