import SwiftUI

enum ThinkingOrbState {
  case breathing
  case searching
  case listening

  var speed: Double {
    switch self {
    case .breathing: 0.55
    case .searching: 1
    case .listening: 1.25
    }
  }
}

/// Nine softly blended particles replace a mechanical spinner in AI moments.
struct ThinkingOrbView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var state: ThinkingOrbState
  var size: CGFloat = 64

  var body: some View {
    Group {
      if reduceMotion {
        orb(at: 0)
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
          orb(at: context.date.timeIntervalSinceReferenceDate * state.speed)
        }
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private func orb(at time: TimeInterval) -> some View {
    Canvas { context, canvasSize in
      let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
      let palette: [Color] = [.cyan, .blue, .indigo, .purple, .pink, .orange, .mint, .blue, .purple]

      context.addFilter(.blur(radius: size * 0.055))
      for index in 0..<9 {
        let phase = Double(index) * (.pi * 2 / 9)
        let orbit = size * (0.16 + CGFloat(index % 3) * 0.06)
        let angle = time * (0.68 + Double(index % 3) * 0.12) + phase
        let breath = 0.82 + sin(time * 1.4 + phase) * 0.18
        let dot = size * (0.22 + CGFloat(index % 2) * 0.045) * breath
        let point = CGPoint(
          x: center.x + cos(angle) * orbit,
          y: center.y + sin(angle * 1.08) * orbit
        )
        let rect = CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)
        context.opacity = 0.48
        context.fill(Path(ellipseIn: rect), with: .color(palette[index]))
      }
    }
    .background {
      Circle()
        .fill(Color.primary.opacity(0.035))
        .blur(radius: size * 0.08)
    }
    .drawingGroup()
  }
}
