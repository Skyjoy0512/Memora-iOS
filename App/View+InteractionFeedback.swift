import SwiftUI

extension View {
  @MainActor
  func interactionFeedback<Value: Equatable>(
    _ kind: InteractionFeedback.Kind,
    trigger: Value,
    condition: @escaping (Value, Value) -> Bool = { _, _ in true }
  ) -> some View {
    onChange(of: trigger) { oldValue, newValue in
      if condition(oldValue, newValue) {
        InteractionFeedback.shared.send(kind)
      }
    }
  }
}
