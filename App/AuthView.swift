import SwiftUI

/// Optional sign-in. There is no auth service behind it yet, so the screen
/// explains that rather than pretending to create an account.
struct AuthView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var isUnavailableNoticePresented = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Image(icon: .personBadgeKey)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(width: 62, height: 62)
            .background(.primary, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .accessibilityHidden(true)
            .memoraAppear()

          Text("サインインはまだ\n接続されていません。")
            .font(.largeTitle.bold())
            .tracking(-0.7)
            .padding(.top, 22)
            .memoraAppear(delay: 0.05)

          Text("アカウント連携と複数端末の同期は、まだ実装されていません。録音・文字起こし・整理は、このiPhoneの中だけで使えます。")
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .padding(.top, 12)
            .memoraAppear(delay: 0.1)

          VStack(spacing: 10) {
            AuthProviderButton(provider: .apple, isProminent: true) { showUnavailable() }
            AuthProviderButton(provider: .google) { showUnavailable() }
            AuthProviderButton(provider: .email) { showUnavailable() }
          }
          .padding(.top, 30)
          .memoraAppear(delay: 0.15)

          Label("録音そのものは、サインインの有無にかかわらずこのiPhoneに保存されます。", icon: .lockShield)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 26)
            .memoraAppear(delay: 0.25)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.bottom, 28)
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("アカウント")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("あとで", icon: .xmark) { dismiss() }
        }
      }
      .alert("サインインは準備中です", isPresented: $isUnavailableNoticePresented) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("アカウント連携と同期はまだ実装されていません。今はこのiPhoneの中で動作します。")
      }
    }
  }

  private func showUnavailable() {
    isUnavailableNoticePresented = true
  }
}
