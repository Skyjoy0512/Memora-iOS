import SwiftUI

struct MeetingDetailToolbarActions: View {
  var hasAudio: Bool
  var isPlaying: Bool
  var isRecording: Bool
  var play: () -> Void
  var share: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var namespace
  @State private var isPlayRevealed = false
  @State private var isSeparated = false

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        GlassEffectContainer(spacing: 10) {
          HStack(spacing: isSeparated || reduceMotion ? 12 : 0) {
            if hasAudio, isPlayRevealed || reduceMotion {
              playButton
                .glassEffect(.regular.interactive(), in: Circle())
                .glassEffectID("play", in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
            }
            shareButton
              .glassEffect(.regular.interactive(), in: Circle())
              .glassEffectID("share", in: namespace)
          }
        }
      } else {
        HStack(spacing: 12) {
          if hasAudio {
            playButton
          }
          shareButton
        }
      }
    }
    .task(id: hasAudio) {
      isPlayRevealed = false
      isSeparated = false
      guard hasAudio, !reduceMotion else { return }
      do {
        try await Task.sleep(for: .milliseconds(180))
        try Task.checkCancellation()
        withAnimation(.smooth(duration: 0.25)) {
          isPlayRevealed = true
        }
        try await Task.sleep(for: .milliseconds(150))
        try Task.checkCancellation()
        withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
          isSeparated = true
        }
      } catch {
        return
      }
    }
  }

  private var playButton: some View {
    Button(action: play) {
      Image(icon: isPlaying ? .pauseFill : .playFill)
        .font(.headline.weight(.bold))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isRecording)
    .accessibilityLabel(isPlaying ? "一時停止" : "再生")
    .accessibilityIdentifier(isPlaying ? MemoraIcon.pauseFill.rawValue : MemoraIcon.playFill.rawValue)
  }

  private var shareButton: some View {
    Button(action: share) {
      Image(icon: .squareAndArrowUp)
        .font(.headline)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("共有")
    .accessibilityIdentifier(MemoraIcon.squareAndArrowUp.rawValue)
  }
}
