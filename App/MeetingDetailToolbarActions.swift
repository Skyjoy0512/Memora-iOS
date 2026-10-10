import SwiftUI

struct MeetingDetailToolbarActions: View {
  var primaryTitle: LocalizedStringKey = "共有"
  var primaryIcon: MemoraIcon = .squareAndArrowUp
  var primaryArtwork: MemoraArtwork? = nil
  var morphsFromLibrary = false
  var onReplaceIcons: () -> Void = {}
  var hasAudio: Bool
  var isPlaying: Bool
  var isRecording: Bool
  var play: () -> Void
  var share: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var namespace
  @State private var hasReplacedIcons = false
  @State private var isPlayRevealed = false
  @State private var isSeparated = false

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 12) {
            if hasAudio {
              Color.clear
                .frame(width: 44, height: 44)
                .overlay {
                  if isPlayRevealed || reduceMotion {
                    playButton
                      .glassEffect(.regular.interactive(), in: Circle())
                      .glassEffectID("play", in: namespace)
                      .offset(x: isSeparated || reduceMotion ? 0 : 56)
                  }
                }
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
    .frame(width: hasAudio ? 100 : 44, height: 44)
    .task(id: hasAudio) {
      guard !reduceMotion else {
        hasReplacedIcons = true
        onReplaceIcons()
        isPlayRevealed = hasAudio
        isSeparated = true
        return
      }
      do {
        if morphsFromLibrary, !hasReplacedIcons {
          try await Task.sleep(for: .milliseconds(300))
          try Task.checkCancellation()
          withAnimation(.smooth(duration: 0.2)) {
            hasReplacedIcons = true
            onReplaceIcons()
          }
          try await Task.sleep(for: .milliseconds(220))
        }
        guard hasAudio else {
          isPlayRevealed = false
          isSeparated = false
          return
        }
        guard !isPlayRevealed else { return }
        if !morphsFromLibrary {
          try await Task.sleep(for: .milliseconds(180))
        }
        try Task.checkCancellation()
        isPlayRevealed = true
        try await Task.sleep(for: .milliseconds(32))
        try Task.checkCancellation()
        withAnimation(.spring(duration: 0.45, bounce: 0)) {
          isSeparated = true
        }
      } catch {
        if !isSeparated {
          isPlayRevealed = false
        }
        return
      }
    }
  }

  private var playButton: some View {
    Button(action: play) {
      ToolbarIconGlyph(icon: isPlaying ? .pauseFill : .playFill)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isRecording)
    .accessibilityLabel(isPlaying ? "一時停止" : "再生")
    .accessibilityIdentifier(isPlaying ? MemoraIcon.pauseFill.rawValue : MemoraIcon.playFill.rawValue)
    .allowsHitTesting(isSeparated || reduceMotion)
    .accessibilityHidden(!isSeparated && !reduceMotion)
  }

  private var shareButton: some View {
    Button(action: share) {
      Group {
        if morphsFromLibrary && !hasReplacedIcons && !reduceMotion {
          ToolbarIconGlyph(icon: .magnifyingglass)
        } else {
          ToolbarIconGlyph(icon: primaryIcon, artwork: primaryArtwork)
        }
      }
        .contentTransition(reduceMotion ? .identity : .opacity)
        .font(.headline)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(primaryTitle)
    .accessibilityIdentifier(primaryIcon.rawValue)
  }
}
