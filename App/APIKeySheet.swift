import SwiftUI

struct APIKeySheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  var provider: String
  var account: String
  /// Set for a language model provider, to show its mark and where to get a key.
  var llmProvider: LLMProvider? = nil
  /// Called after a key is saved or removed, so the caller can refresh.
  var onChange: () -> Void = {}
  @State private var key = ""
  @State private var hasStoredKey = false

  init(provider: String, account: String) {
    self.provider = provider
    self.account = account
  }

  init(llmProvider: LLMProvider, onChange: @escaping () -> Void = {}) {
    self.provider = llmProvider.label
    self.account = llmProvider.keychainAccount
    self.llmProvider = llmProvider
    self.onChange = onChange
  }

  /// Keys are often pasted with a trailing newline or space, which the API
  /// would reject as a wrong key.
  private var trimmedKey: String {
    key.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        if let llmProvider {
          Section {
            HStack(spacing: 14) {
              ProviderLogo(provider: llmProvider, size: 44)
              VStack(alignment: .leading, spacing: 2) {
                Text(llmProvider.label)
                  .font(.headline)
                Text(llmProvider.company)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, MemoraSpacing.xs)
          }
        }

        Section {
          SecureField(llmProvider?.keyPlaceholder ?? "キーを入力", text: $key)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          if hasStoredKey {
            Label("保存済みのキーがあります", icon: .checkmarkSealFill)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("\(provider) のAPIキー")
        } footer: {
          Text("キーチェーンに保存し、設定画面にも再表示しません。新しいキーを入れると置き換わります。")
        }

        if let llmProvider {
          Section {
            Button("\(llmProvider.company)でキーを作成", icon: .arrowUpRightSquare) {
              openURL(llmProvider.keyConsoleURL)
            }
          } footer: {
            if let note = llmProvider.note {
              Text(note)
            }
          }
        }

        if hasStoredKey {
          Section {
            Button("キーを削除", icon: .trash, role: .destructive) {
              KeychainStore.set(nil, forKey: account)
              hasStoredKey = false
              onChange()
              dismiss()
            }
          }
        }
      }
      .navigationTitle("APIキー")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            KeychainStore.set(trimmedKey, forKey: account)
            hasStoredKey = true
            onChange()
            dismiss()
          }
          .disabled(trimmedKey.isEmpty)
        }
      }
    }
    .presentationDetents(llmProvider == nil ? [.medium] : [.medium, .large])
    .onAppear {
      hasStoredKey = KeychainStore.has(account)
    }
  }
}
