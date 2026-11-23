import SwiftUI

/// Optional sign-in. There is no auth service behind the Apple, Google and
/// e-mail buttons yet, so those explain that rather than pretending to
/// create an account. ChatGPT sign-in is connected and opens the browser.
struct AuthView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MemoraModel.self) private var model

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("アカウント連携")
            .font(MemoraTypography.display)
            .accessibilityAddTraits(.isHeader)

          Text("ログインせず、このiPhoneで使えます。ChatGPTのアカウントを連携すると、ChatGPTの権限に応じて利用できます。")
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .padding(.top, MemoraSpacing.md)

          Button { dismiss() } label: {
            Text("このiPhoneで続ける").frame(maxWidth: .infinity)
          }
            .buttonStyle(MemoraButtonStyle())
            .padding(.top, MemoraSpacing.section)
            .accessibilityIdentifier("auth.continueLocal")

          VStack(spacing: MemoraSpacing.sm) {
            AuthProviderButton(provider: .chatGPT) {
              Task { await model.signInWithChatGPT() }
            }
            .disabled(model.isChatGPTSigningIn)

            AuthProviderButton(provider: .apple)
            AuthProviderButton(provider: .google)
            AuthProviderButton(provider: .email)
          }
          .padding(.top, MemoraSpacing.section)

          if let message = model.chatGPTSignInFailureMessage {
            Text(message)
              .font(.footnote)
              .foregroundStyle(MemoraPalette.danger)
              .padding(.top, MemoraSpacing.sm)
          }

          if model.hasChatGPTPlanUsage {
            HStack(spacing: MemoraSpacing.xs) {
              Image(icon: .checkmarkCircle, size: 14)
              Text("ChatGPTの計画的な利用が許可されています。")
            }
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.top, MemoraSpacing.sm)
          }

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
    }
  }
}
