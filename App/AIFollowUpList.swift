import SwiftUI

/// Questions to ask next, under the latest answer. Tapping one asks it.
struct AIFollowUpList: View {
  var prompts: [String]
  var title = "続けて聞く"
  var onSelect: (String) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, MemoraSpacing.xxs)
      ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
        Button {
          onSelect(prompt)
        } label: {
          HStack(spacing: 8) {
            Image(icon: .arrowTurnDownRight, size: 11)
              .foregroundStyle(.tertiary)
            Text(prompt)
              .font(.subheadline)
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
          }
          .padding(.vertical, MemoraSpacing.sm)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : 6)
        .animation(reduceMotion ? nil : MemoraMotion.screen.delay(Double(index) * 0.09), value: isShown)
        if index < prompts.count - 1 {
          Divider()
        }
      }
    }
    .padding(.top, MemoraSpacing.xs)
    .onAppear { isShown = true }
  }
}
