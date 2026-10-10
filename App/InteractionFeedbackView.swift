import SwiftUI

struct InteractionFeedbackView: View {
  private var feedback: InteractionFeedback { .shared }

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .sensoryFeedback(trigger: feedback.event) { _, event in
        feedback.canPlay ? event?.kind.sensoryFeedback : nil
      }
  }
}
