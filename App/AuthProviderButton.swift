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
        .padding(.vertical, 15)
        .foregroundStyle(isProminent ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.primary))
        .background {
          let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
          if isProminent {
            shape.fill(.primary)
          } else {
            shape.fill(Color(uiColor: .secondarySystemBackground))
          }
        }
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
