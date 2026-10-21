import SwiftUI

/// The opaque cover shown while Memora is locked. It shows the app's mark and a
/// button that asks for Face ID (or the passcode).
struct LockScreenView: View {
  var onUnlock: () -> Void
  var authenticationMessage: String? = nil
  var isAuthenticating = false

  var body: some View {
    ZStack {
      Color(uiColor: .systemBackground).ignoresSafeArea()

      VStack(spacing: 20) {
        Image(icon: .lockShieldFill, size: 44)
          .font(.system(size: 44, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 84, height: 84)
          .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
          .accessibilityHidden(true)

        VStack(spacing: 6) {
          Text("Memoraはロックされています")
            .font(.headline)
          Text("Face IDまたはパスコードで解除します。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if let authenticationMessage {
          Text(authenticationMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        Button(action: onUnlock) {
          Label(isAuthenticating ? "認証しています…" : "ロックを解除", icon: .faceid)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MemoraButtonStyle())
        .disabled(isAuthenticating)
      }
      .padding(MemoraSpacing.section)
      .frame(maxWidth: 360)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Memoraはロックされています")
  }
}
