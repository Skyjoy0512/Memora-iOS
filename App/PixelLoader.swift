import SwiftUI

/// A 3×3 pixel grid for long-running work: a chevron wavefront driving right
/// (`drive`, `dots`) or a comet lapping the edge (`orbit`). Reduce Motion
/// leaves the grid still and dim.
struct PixelLoader: View {
  enum Pattern {
    case drive
    case dots
    case orbit
  }

  var pattern: Pattern = .drive
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Each cell's delay in seconds, or nil for a cell that stays dark.
  private var delays: [Double?] {
    switch pattern {
    case .drive, .dots:
      return (0..<9).map { index in
        let row = index / 3, column = index % 3
        return Double(column + abs(row - 1)) * 0.09
      }
    case .orbit:
      let order = [0, 1, 2, 5, 8, 7, 6, 3]
      return (0..<9).map { index in order.firstIndex(of: index).map { Double($0) * 0.11 } }
    }
  }

  private var cycle: Double { pattern == .orbit ? 0.95 : 0.65 }

  var body: some View {
    let delays = delays
    TimelineView(.animation(paused: reduceMotion)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
        ForEach(0..<3, id: \.self) { row in
          GridRow {
            ForEach(0..<3, id: \.self) { column in
              let delay = delays[row * 3 + column]
              cell
                .opacity(opacity(delay: delay, time: time))
            }
          }
        }
      }
    }
    .accessibilityHidden(true)
  }

  private var cell: some View {
    Group {
      if pattern == .dots {
        Circle().fill(.primary)
      } else {
        RoundedRectangle(cornerRadius: 1).fill(.primary)
      }
    }
    .frame(width: 4, height: 4)
  }

  /// Dim by default; a cell lights as the wave passes it.
  private func opacity(delay: Double?, time: Double) -> Double {
    guard let delay else { return 0.07 }
    guard !reduceMotion else { return 0.15 }
    let phase = ((time - delay).truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle) / cycle
    // On for the first part of the cycle, easing back to dim.
    let lit = phase < 0.5 ? sin(phase / 0.5 * .pi) : 0
    return 0.15 + 0.85 * lit
  }
}
