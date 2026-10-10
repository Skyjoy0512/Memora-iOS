import SwiftUI

/// What Ask AI opens with before anything is asked: a large welcoming title,
/// chosen at random each time.
struct AskAIGreeting: View {
  /// Picked once per opening, so the title does not change as the screen redraws.
  @State private var title = Self.titles.randomElement() ?? "何をお手伝いしましょう"

  private static let titles = [
    "何をお手伝いしましょう",
    "今日は何をしましょうか",
    "何かお手伝いできることは？",
    "どこから始めましょうか",
    "今日は何をお探しですか"
  ]

  var body: some View {
    Text(title)
      .font(.title2.weight(.regular))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .memoraTextReveal()
      .frame(maxWidth: .infinity)
  }
}
