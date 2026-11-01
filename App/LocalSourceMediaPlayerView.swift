import AVKit
import SwiftUI

struct LocalSourceMediaPlayerView: View {
  var url: URL
  var title: String
  var start: TimeInterval?
  @State private var video = SourceVideoPlayback()
  @State private var scopedURL: URL?

  var body: some View {
    Group {
      if SourceIntake.kind(for: url) == .video {
        ZStack {
          if let player = video.player {
            VideoPlayer(player: player)
          } else {
            VStack(spacing: 16) {
              if let notice = video.notice { Text(notice).foregroundStyle(.secondary) }
              Button("再生", icon: .playFill) { Task { await video.load(url, start: start) } }
                .buttonStyle(MemoraButtonStyle())
            }
          }
        }
        .task(id: url) { await video.load(url, start: start) }
        .onDisappear { video.stop() }
      } else {
        LocalSourceAudioControls(url: url, title: title, start: start)
      }
    }
    .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if scopedURL == nil, url.startAccessingSecurityScopedResource() { scopedURL = url }
    }
    .onDisappear {
      scopedURL?.stopAccessingSecurityScopedResource()
      scopedURL = nil
    }
  }
}

private struct LocalSourceAudioControls: View {
  var url: URL
  var title: String
  var start: TimeInterval?
  @State private var player = AudioPlayerService()

  var body: some View {
    VStack(spacing: 24) {
      Text(title).font(.title2).multilineTextAlignment(.center)
      if let failure = player.errorMessage { Text(failure).foregroundStyle(.secondary) }
      Text(MemoraFormat.duration(player.currentTime) + " / " + MemoraFormat.duration(player.duration))
        .font(.body.monospacedDigit())
      Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
        in: 0...max(1, player.duration)) { Text("再生位置") }
      Button(player.isPlaying ? "一時停止" : "再生", icon: player.isPlaying ? .pauseFill : .playFill) { player.toggle() }
        .buttonStyle(MemoraButtonStyle())
    }
    .padding(MemoraSpacing.screen)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: url) {
      player.load(url, title: title)
      if let time = ProjectCitationLocation.playbackTime(start) { player.seek(to: time); player.play() }
    }
    .onDisappear { player.stop() }
  }
}
