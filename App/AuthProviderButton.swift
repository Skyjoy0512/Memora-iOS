import SwiftUI

struct AuthProviderButton: View {
  var provider: AuthProvider
  var isProminent = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        HStack(spacing: 12) {
          providerIcon
          Text(provider.signInTitle)
        }
        Text("準備中").font(.footnote)
      }
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(MemoraButtonStyle(emphasis: isProminent ? .primary : .secondary))
    .accessibilityHint("認証は未接続です。案内を表示します。")
  }

  @ViewBuilder private var providerIcon: some View {
    switch provider {
    case .google:
      Image("account.google").renderingMode(.original).resizable().scaledToFit()
        .padding(2).frame(width: 24, height: 24)
        .background(.white, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    case .apple:
      // Apple's unmodified sign-in mark is a brand identity, not an interface glyph.
      Image(systemName: "apple.logo").resizable().scaledToFit()
        .frame(width: 20, height: 20).accessibilityHidden(true)
    case .email:
      Image(icon: .envelope, size: 20).accessibilityHidden(true)
    }
  }
}
