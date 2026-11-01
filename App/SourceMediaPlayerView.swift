import AVKit
import SwiftUI

struct SourceMediaPlayerView: View {
  @Environment(MemoraModel.self) private var model
  var sourceID: UUID
  var start: TimeInterval?
  @State private var video = SourceVideoPlayback()

  var body: some View {
    if let source = model.source(id: sourceID), let name = source.localFileReference,
       let url = ProjectSourceFiles.resolve(name) {
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
          SourceAudioPlaybackControls(url: url, title: source.title, start: start)
        }
      }
      .navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
    } else { ContentUnavailableView("ファイルが見つかりません", icon: .docQuestionmark) }
  }
}

private struct SourceAudioPlaybackControls: View {
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
