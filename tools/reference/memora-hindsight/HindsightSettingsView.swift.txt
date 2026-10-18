import SwiftUI

/// Connects a Hindsight memory server so Ask AI remembers across conversations:
/// recall before an answer, retain after it. Nothing is shown as working until
/// the server really answers.
struct HindsightSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var token = ""
  @State private var hasToken = false
  @State private var status: String?
  @State private var isTesting = false

  var body: some View {
    @Bindable var model = model

    return Form {
      Section {
        Toggle("Hindsightを使う", isOn: $model.hindsightConfig.isEnabled)
      } footer: {
        Text("オンにすると、質問の前にHindsightから記憶を呼び出し、回答のあとに会話を保存します。使うほど回答が自分向けになります。")
      }

      Section {
        TextField("http://localhost:8888", text: $model.hindsightConfig.baseURL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
        TextField("memora", text: $model.hindsightConfig.bankID)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      } header: {
        Text("接続先")
      } footer: {
        Text("自前のHindsightサーバー（既定は http://localhost:8888）か、Hindsight CloudのURL。bank idは記憶を入れる「脳」の名前で、利用者ごとに分けられます。")
      }

      Section {
        SecureField(hasToken ? "保存済み（変更する場合のみ入力）" : "APIキー", text: $token)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("キーを保存") {
          KeychainStore.set(token.isEmpty ? nil : token, forKey: HindsightConfig.tokenAccount)
          token = ""
          hasToken = KeychainStore.has(HindsightConfig.tokenAccount)
        }
        .disabled(token.isEmpty)
        if hasToken {
          Button("キーを削除", role: .destructive) {
            KeychainStore.set(nil, forKey: HindsightConfig.tokenAccount)
            hasToken = false
          }
        }
      } header: {
        Text("APIキー")
      } footer: {
        Text("Hindsight CloudはAPIキーが必要です。キーはKeychainに保存し、設定画面にも再表示しません。")
      }

      Section {
        Button {
          test()
        } label: {
          HStack(spacing: 12) {
            SettingsIcon(icon: .arrowClockwise, color: .teal)
            Text("接続を確認")
            if isTesting {
              Spacer(minLength: 8)
              ProgressView()
            }
          }
        }
        .disabled(isTesting || !model.hindsightConfig.isConfigured)
        if let status {
          Text(status)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } footer: {
        Text("接続先とキーが正しいかを、Hindsightの /health で確かめます。")
      }
    }
    .navigationTitle("Hindsight")
    .memoraBackButton()
    .onAppear { hasToken = KeychainStore.has(HindsightConfig.tokenAccount) }
  }

  private func test() {
    isTesting = true
    status = nil
    let config = model.hindsightConfig
    Task {
      do {
        status = try await HindsightClient.check(
          config: config,
          token: KeychainStore.string(forKey: HindsightConfig.tokenAccount)
        )
      } catch {
        status = error.localizedDescription
      }
      isTesting = false
    }
  }
}
