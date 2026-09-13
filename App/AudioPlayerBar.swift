import SwiftUI

struct AudioPlayerBar: View {
  var meeting: Meeting
  @State private var player = AudioPlaybackService()

  var body: some View {
    HStack(spacing: 12) {
      Button(player.isPlaying ? "一時停止" : "再生", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
        player.togglePlayback()
      }
      .labelStyle(.iconOnly)
      .font(.headline)
      .frame(width: 40, height: 40)
      .background(.indigo, in: Circle())
      .foregroundStyle(.white)

      VStack(spacing: 4) {
        Slider(
          value: Binding {
            player.currentTime / max(player.duration, 1)
          } set: { newValue in
            player.seek(to: newValue)
          },
          in: 0...1
        ) {
          Text("音声の再生位置")
        }

        HStack {
          Text(MemoraFormat.duration(player.currentTime))
          Spacer()
          Text(MemoraFormat.duration(player.duration))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.regularMaterial)
    .onAppear {
      player.configure(url: meeting.audioURL, fallbackDuration: meeting.duration)
    }
    .onDisappear {
      player.stop()
    }
    .accessibilityElement(children: .contain)
  }
}
