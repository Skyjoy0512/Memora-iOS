import SwiftUI

/// A small, quiet picture of what the page promises, so the copy has something
/// concrete next to it.
struct OnboardingPreview: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var page: OnboardingPage
  var isCurrent: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch page {
      case .record:
        recordPreview
      case .understand:
        understandPreview
      case .act:
        actPreview
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .memoraCard(radius: 20)
    .accessibilityHidden(true)
  }

  private var recordPreview: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(.red)
        .frame(width: 9, height: 9)
        .opacity(isCurrent && !reduceMotion ? 1 : 0.5)
        .animation(
          reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
          value: isCurrent
        )

      HStack(spacing: 3) {
        ForEach(0..<22, id: \.self) { index in
          Capsule()
            .fill(.primary.opacity(0.35))
            .frame(width: 3, height: barHeight(index))
        }
      }

      Spacer(minLength: 0)

      Text("00:42")
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
    }
    .frame(height: 30)
  }

  private var understandPreview: some View {
    VStack(alignment: .leading, spacing: 10) {
      PreviewLabel(title: "サマリー", symbol: "sparkles")
      PreviewLine(widthRatio: 1)
      PreviewLine(widthRatio: 0.82)

      Divider()

      PreviewLabel(title: "決まったこと", symbol: "checkmark.seal.fill")
      PreviewLine(widthRatio: 0.66)
    }
  }

  private var actPreview: some View {
    VStack(alignment: .leading, spacing: 12) {
      PreviewTask(isCompleted: false, widthRatio: 0.78)
      PreviewTask(isCompleted: true, widthRatio: 0.58)
    }
  }

  /// A fixed, repeating silhouette so the waveform reads as speech.
  private func barHeight(_ index: Int) -> CGFloat {
    let pattern: [CGFloat] = [8, 16, 24, 13, 20, 9, 26, 14]
    return pattern[index % pattern.count]
  }
}

private struct PreviewLabel: View {
  var title: String
  var symbol: String

  var body: some View {
    Label(title, systemImage: symbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
  }
}

private struct PreviewLine: View {
  var widthRatio: CGFloat

  var body: some View {
    Capsule()
      .fill(.primary.opacity(0.16))
      .frame(height: 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .scaleEffect(x: widthRatio, anchor: .leading)
  }
}

private struct PreviewTask: View {
  var isCompleted: Bool
  var widthRatio: CGFloat

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
        .font(.body)
        .foregroundStyle(isCompleted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      PreviewLine(widthRatio: widthRatio)
        .opacity(isCompleted ? 0.6 : 1)
    }
  }
}

