import SwiftUI

/// Questions to ask next, under the latest answer. Tapping one asks it.
struct AIFollowUpList: View {
  var prompts: [String]
  var onSelect: (String) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("続けて聞く")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
      ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
        Button {
          onSelect(prompt)
        } label: {
          HStack(spacing: 8) {
            Image(icon: .arrowTurnDownRight)
              .font(.caption2)
              .foregroundStyle(.tertiary)
            Text(prompt)
              .font(.subheadline)
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 8)
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
    .padding(.top, 4)
    .onAppear { isShown = true }
  }
}
