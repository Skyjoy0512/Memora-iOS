import SwiftUI

/// Creating an account or logging back in with an email address.
struct EmailAuthView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var mode: Mode
  var onFinish: () -> Void

  @State private var selectedMode: Mode
  @State private var name = ""
  @State private var email = ""
  @State private var password = ""
  @State private var errorMessage: String?
  @State private var isWorking = false
  @State private var isUnavailableNoticePresented = false
  @FocusState private var focusedField: Field?

  init(mode: Mode, onFinish: @escaping () -> Void) {
    self.mode = mode
    self.onFinish = onFinish
    _selectedMode = State(initialValue: mode)
  }

  var body: some View {
    MemoraForm {
      Section {
        MemoraSectionPicker(items: Mode.allCases, selection: $selectedMode, title: \.label)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
        .listRowBackground(Color.clear)
      }

      Section {
        if selectedMode == .signUp {
          TextField("名前", text: $name)
            .textContentType(.name)
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit { focusedField = .email }
        }

        TextField("メールアドレス", text: $email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($focusedField, equals: .email)
          .submitLabel(.next)
          .onSubmit { focusedField = .password }

        SecureField("パスワード", text: $password)
          .textContentType(selectedMode == .signUp ? .newPassword : .password)
          .focused($focusedField, equals: .password)
          .submitLabel(.go)
          .onSubmit(submit)
      } footer: {
        if let errorMessage {
          Label(errorMessage, icon: .exclamationmarkCircle)
            .font(.footnote)
            .foregroundStyle(.red)
            .transition(.opacity)
        } else {
          Text(selectedMode.footer)
        }
      }

      Section {
        Button(action: submit) {
          HStack(spacing: 8) {
            if isWorking {
              ProgressView()
                .controlSize(.small)
                .tint(MemoraPalette.actionLabel)
            }
            Text(selectedMode.actionTitle)
              .font(.headline)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(MemoraButtonStyle())
        .disabled(!canSubmit)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)

        if selectedMode == .logIn {
          Button("パスワードをお忘れですか？") {
            focusedField = nil
            isUnavailableNoticePresented = true
          }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
            .listRowBackground(Color.clear)
        }
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: selectedMode)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: errorMessage)
    .navigationTitle(selectedMode.label)
    .navigationBarTitleDisplayMode(.inline)
    .alert("アカウントはまだ接続されていません", isPresented: $isUnavailableNoticePresented) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text("この画面からはアカウントを作成・ログインできません。端末には何も保存していません。")
    }
    .onAppear {
      focusedField = selectedMode == .signUp ? .name : .email
    }
    .onChange(of: selectedMode) {
      errorMessage = nil
    }
  }

  private var trimmedEmail: String {
    email.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSubmit: Bool {
    !isWorking && !trimmedEmail.isEmpty && !password.isEmpty
      && (selectedMode == .logIn || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func submit() {
    guard canSubmit else { return }
    focusedField = nil

    guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
      errorMessage = "メールアドレスの形式を確認してください。"
      return
    }
    guard password.count >= 8 else {
      errorMessage = "パスワードは8文字以上にしてください。"
      return
    }

    // Accounts are not connected yet, so this explains that instead of creating
    // a local account and showing a sign-in that did not happen.
    isUnavailableNoticePresented = true
  }

  enum Mode: String, CaseIterable, Identifiable, Hashable {
    case signUp
    case logIn

    var id: Self { self }

    var label: String {
      switch self {
      case .signUp:
        "新規登録"
      case .logIn:
        "ログイン"
      }
    }

    var actionTitle: String {
      switch self {
      case .signUp:
        "アカウントを作成"
      case .logIn:
        "ログイン"
      }
    }

    var footer: String {
      switch self {
      case .signUp:
        "パスワードは8文字以上。登録後はいつでも設定からアカウントを削除できます。"
      case .logIn:
        "登録したメールアドレスとパスワードを入力してください。"
      }
    }
  }

  private enum Field: Hashable {
    case name
    case email
    case password
  }
}
