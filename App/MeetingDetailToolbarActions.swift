import SwiftUI

/// Native toolbar items stay immediately available; UIKit owns their glass
/// grouping and navigation transition instead of staged icon replacements.
struct MeetingDetailToolbarActions: ToolbarContent {
  var hasAudio: Bool
  var isPlaying: Bool
  var isRecording: Bool
  var play: () -> Void
  var share: () -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      if hasAudio {
        ToolbarIconButton(isPlaying ? "一時停止" : "再生", icon: isPlaying ? .pauseFill : .playFill, action: play)
          .disabled(isRecording)
          .accessibilityIdentifier(isPlaying ? MemoraIcon.pauseFill.rawValue : MemoraIcon.playFill.rawValue)
      }
      ToolbarIconButton("共有", icon: .squareAndArrowUp, action: share)
        .accessibilityIdentifier(MemoraIcon.squareAndArrowUp.rawValue)
    }
  }
}
