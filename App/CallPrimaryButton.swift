import SwiftUI

/// The full-width button at the bottom of each call setup screen.
struct CallPrimaryButton: View {
  var title: String
  var icon: MemoraIcon?
  var isEnabled = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Image(icon: icon) }
        Text(title)
      }
      .font(.headline)
      .foregroundStyle(Color(uiColor: .systemBackground))
      .frame(maxWidth: .infinity, minHeight: 54)
      .background(isEnabled ? Color.primary : Color.secondary.opacity(0.5), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
  }
}
