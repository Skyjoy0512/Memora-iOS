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
          Image(icon: .personBadgeKey, size: 28)
            .foregroundStyle(MemoraPalette.textPrimary)
            .accessibilityHidden(true)

          Text("サインインはまだ\n接続されていません。")
            .font(MemoraTypography.display)
            .padding(.top, MemoraSpacing.xxl)

          Text("アカウント連携と複数端末の同期は、まだ実装されていません。録音・文字起こし・整理は、このiPhoneの中だけで使えます。")
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .padding(.top, MemoraSpacing.md)

          VStack(spacing: 10) {
            AuthProviderButton(provider: .apple, isProminent: true) { showUnavailable() }
            AuthProviderButton(provider: .google) { showUnavailable() }
            AuthProviderButton(provider: .email) { showUnavailable() }
          }
          .padding(.top, MemoraSpacing.section)

          Label("録音そのものは、サインインの有無にかかわらずこのiPhoneに保存されます。", icon: .lockShield)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, MemoraSpacing.xxl)
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.xxl)
        .padding(.bottom, MemoraSpacing.section)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .background(MemoraPalette.background)
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
