import Lottie
import SwiftUI

/// Draws one icon either from an asset-catalog image (SVG/PDF, used where an
/// animation cannot run) or from a Lottie file. Callers pick the variant pair
/// (solid/outline) by passing the matching names, so an icon's selection state
/// and its context — tab bar versus a screen — stay decoupled.
struct MemoraIconView: View {
  var staticName: String
  var animationName: String?
  var prefersAnimation = false
  var isPlaying = true
  var loopMode: LottieLoopMode = .loop

  var body: some View {
    if prefersAnimation, let animationName, LottieAnimation.named(animationName) != nil {
      LottieView(animation: .named(animationName))
        .playbackMode(playbackMode)
        .resizable()
    } else {
      Image(staticName)
        .resizable()
        .scaledToFit()
    }
  }

  private var playbackMode: LottiePlaybackMode {
    isPlaying
      ? .playing(.fromProgress(nil, toProgress: 1, loopMode: loopMode))
      : .paused(at: .currentFrame)
  }
}
