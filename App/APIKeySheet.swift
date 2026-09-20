import SwiftUI

struct APIKeySheet: View {
  @Environment(\.dismiss) private var dismiss
  var provider: String
  var account: String
  @State private var key = ""
  @State private var hasStoredKey = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("キーを入力", text: $key)
            .textContentType(.password)
        } header: {
          Text("\(provider) のAPIキー")
        } footer: {
          Text("キーチェーンに保存し、設定画面にも再表示しません。")
        }

        if hasStoredKey {
          Section {
            Button("キーを削除", systemImage: "trash", role: .destructive) {
              KeychainStore.set(nil, forKey: account)
              hasStoredKey = false
              dismiss()
            }
          }
        }
      }
      .navigationTitle("APIキーを設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("安全に保存") {
            KeychainStore.set(key, forKey: account)
            hasStoredKey = true
            dismiss()
          }
          .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
    .onAppear {
      hasStoredKey = KeychainStore.has(account)
    }
  }
}
