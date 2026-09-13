import SwiftUI

/// Optional sign-in. The HIG asks to delay sign-in for as long as possible, so
/// this is always reachable and always skippable.
struct AuthView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var emailFlow: EmailAuthView.Mode?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Image(systemName: "person.badge.key")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(width: 62, height: 62)
            .background(.primary, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .accessibilityHidden(true)
            .memoraAppear()

          Text("どの端末でも、\n同じ会話の続きから。")
            .font(.largeTitle.bold())
            .tracking(-0.7)
            .padding(.top, 22)
            .memoraAppear(delay: 0.05)

          Text("サインインすると、会議・タスク・プロジェクトをiPhoneとiPadで同期できます。サインインしなくても、録音と整理はこのまま使えます。")
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .padding(.top, 12)
            .memoraAppear(delay: 0.1)

          VStack(spacing: 10) {
            AuthProviderButton(provider: .apple, isProminent: true) {
              signIn(with: .apple)
            }
            AuthProviderButton(provider: .google) {
              signIn(with: .google)
            }
            AuthProviderButton(provider: .email) {
              emailFlow = .signUp
            }
          }
          .padding(.top, 30)
          .memoraAppear(delay: 0.15)

          Button("すでにアカウントをお持ちですか？ ログイン") {
            emailFlow = .logIn
          }
          .font(.subheadline)
          .frame(maxWidth: .infinity)
          .padding(.top, 20)
          .memoraAppear(delay: 0.2)

          Label("録音そのものは、サインインの有無にかかわらずこのiPhoneに保存されます。", systemImage: "lock.shield")
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
          Button("あとで") { dismiss() }
        }
      }
      .navigationDestination(item: $emailFlow) { mode in
        EmailAuthView(mode: mode) { dismiss() }
      }
    }
  }

  private func signIn(with provider: AuthProvider) {
    withAnimation(MemoraMotion.screen) {
      model.signIn(with: provider)
    }
    dismiss()
  }
}

private struct AuthProviderButton: View {
  var provider: AuthProvider
  var isProminent = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(provider.signInTitle, systemImage: provider.symbol)
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
