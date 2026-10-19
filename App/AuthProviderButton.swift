import SwiftUI

struct AuthProviderButton: View {
  var provider: AuthProvider
  var isProminent = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(provider.signInTitle, icon: provider.symbol)
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoraSpacing.lg)
        .foregroundStyle(isProminent ? MemoraPalette.actionLabel : MemoraPalette.textPrimary)
        .background {
          let shape = RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous)
          if isProminent {
            shape.fill(MemoraPalette.action)
          } else {
            shape.fill(MemoraPalette.card)
          }
        }
        .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
