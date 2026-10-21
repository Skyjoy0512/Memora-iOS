import SwiftUI

struct AuthProviderButton: View {
  var provider: AuthProvider
  var isProminent = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(provider.signInTitle, icon: provider.symbol)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(MemoraButtonStyle(emphasis: isProminent ? .primary : .secondary))
  }
}
