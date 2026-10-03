import SwiftUI

/// Long-running work, said plainly: a pixel loader, what is happening, and
/// how long it has really been running. The timer is shown only when the real
/// start time is known.
struct WorkingStatus: View {
  var label: String
  var startedAt: Date?
  var pattern: PixelLoader.Pattern = .drive

  var body: some View {
    HStack(spacing: 10) {
      PixelLoader(pattern: pattern)
      ShimmerText(text: label)
        .font(.subheadline.weight(.medium))
      if let startedAt {
        ElapsedText(since: startedAt)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// Seconds since a moment, ticking: 3.4s, then 1m 12.0s.
struct ElapsedText: View {
  var since: Date

  var body: some View {
    TimelineView(.periodic(from: since, by: 0.1)) { context in
      Text(Self.format(context.date.timeIntervalSince(since)))
    }
  }

  static func format(_ seconds: TimeInterval) -> String {
    let total = max(0, seconds)
    if total < 60 { return String(format: "%.1fs", total) }
    return "\(Int(total) / 60)m " + String(format: "%.1fs", total.truncatingRemainder(dividingBy: 60))
  }
}
