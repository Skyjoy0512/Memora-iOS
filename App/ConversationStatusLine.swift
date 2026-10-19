import SwiftUI

struct ConversationStatusLine: View {
  var label: String
  var since: Date?
  var isWaiting = false
  var showsShimmer = true

  var body: some View {
    HStack(spacing: 8) {
      ThinkingGauge(size: 16, isActive: !isWaiting)
      if isWaiting { Text(label).foregroundStyle(.secondary) }
      else {
        if showsShimmer { ShimmerText(text: label) }
        else { Text(label).foregroundStyle(.secondary) }
        if let since {
          ElapsedText(since: since).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
        }
      }
    }
    .font(.footnote.weight(.medium))
    .padding(.vertical, MemoraSpacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

// A small round gauge marking work in progress, adapted from chatgpt-ios-ui's
// ThinkingGauge (MIT, dc6e6a52); Copyright (c) 2026 Bryan Ramirez-Gonzalez and
// contributors. See App/Resources/ChatGPTUI-LICENSE.txt. Memora changes: the
// monochrome palette, and the accent arc turns while work is under way —
// it holds still for Reduce Motion and while a person's answer is awaited.
private struct ThinkingGauge: View {
  var size: CGFloat = 16
  var isActive = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isTurning: Bool { isActive && !reduceMotion }

  var body: some View {
    TimelineView(.animation(paused: !isTurning)) { context in
      let turn = isTurning ? context.date.timeIntervalSinceReferenceDate * 140 : 0
      ZStack {
        Circle().trim(from: 0.13, to: 0.88)
          .stroke(MemoraPalette.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(90))
        Circle().trim(from: 0.34, to: 0.88)
          .stroke(MemoraPalette.textPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(90 + turn))
        Circle().stroke(MemoraPalette.textPrimary, lineWidth: 1.7)
          .frame(width: size * 0.28, height: size * 0.28)
        Capsule().fill(MemoraPalette.textPrimary)
          .frame(width: 2, height: size * 0.55)
          .offset(y: -size * 0.22)
          .rotationEffect(.degrees(43))
      }
      .frame(width: size, height: size)
    }
    .accessibilityHidden(true)
  }
}
