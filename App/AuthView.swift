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
          Text("Memoraで始める")
            .font(MemoraTypography.display)
            .accessibilityAddTraits(.isHeader)

          Text("ログインせず、このiPhoneで使えます。アカウント連携と複数端末の同期は準備中です。")
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .padding(.top, MemoraSpacing.md)

          VStack(spacing: 10) {
            AuthProviderButton(provider: .apple) { showUnavailable() }
            AuthProviderButton(provider: .google) { showUnavailable() }
            AuthProviderButton(provider: .email) { showUnavailable() }
          }
          .padding(.top, MemoraSpacing.section)

          Button { dismiss() } label: {
            Text("ログインせず利用").frame(maxWidth: .infinity)
          }
            .buttonStyle(MemoraButtonStyle())
            .padding(.top, MemoraSpacing.section)
            .accessibilityIdentifier("auth.continueLocal")

          Text("録音はこのiPhoneに保存されます。クラウドAIを設定した場合は、許可した内容を送信します。")
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
        Text("認証サービスは未接続です。アカウントは作成されません。ログインせず利用できます。")
      }
    }
  }

  private func showUnavailable() {
    isUnavailableNoticePresented = true
  }
}
