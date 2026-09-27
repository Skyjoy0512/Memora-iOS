import SwiftUI

/// The opaque cover shown while Memora is locked. It shows the app's mark and a
/// button that asks for Face ID (or the passcode).
struct LockScreenView: View {
  var onUnlock: () -> Void

  var body: some View {
    ZStack {
      Color(uiColor: .systemBackground).ignoresSafeArea()

      VStack(spacing: 20) {
        Image(icon: .lockShieldFill)
          .font(.system(size: 44, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 84, height: 84)
          .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          .accessibilityHidden(true)

        VStack(spacing: 6) {
          Text("Memoraはロックされています")
            .font(.headline)
          Text("Face IDで解除します。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Button("ロックを解除", icon: .faceid, action: onUnlock)
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, minHeight: 52)
          .background(.tint, in: Capsule())
          .contentShape(Capsule())
          .buttonStyle(.plain)
      }
      .padding(28)
      .frame(maxWidth: 360)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Memoraはロックされています")
  }
}
