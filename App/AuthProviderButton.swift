import SwiftUI

struct AuthProviderButton: View {
  var provider: AuthProvider
  var isProminent = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Label(provider.signInTitle, icon: provider.symbol)
        Text("準備中").font(.footnote)
      }
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(MemoraButtonStyle(emphasis: isProminent ? .primary : .secondary))
    .accessibilityHint("認証は未接続です。案内を表示します。")
  }
}
