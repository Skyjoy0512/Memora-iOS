import SwiftUI

/// Every supported provider with its mark, and whether a key is saved for it.
struct LLMProviderPickerView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var savedKeys: Set<LLMProvider> = []

  var body: some View {
    MemoraForm {
      Section {
        ForEach(LLMProvider.allCases) { provider in
          Button {
            model.aiProvider = provider
            dismiss()
          } label: {
            HStack(spacing: 12) {
              ProviderLogo(provider: provider, size: 34)
              VStack(alignment: .leading, spacing: 2) {
                Text(provider.label)
                  .foregroundStyle(.primary)
                Text(savedKeys.contains(provider) ? "\(provider.company) · キー保存済み" : provider.company)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 8)
              if provider == model.aiProvider {
                Image(icon: .checkmark, size: 17)
                  .foregroundStyle(.primary)
              }
            }
            .contentShape(Rectangle())
          }
          .accessibilityAddTraits(provider == model.aiProvider ? .isSelected : [])
        }
      } footer: {
        Text("キーは各社の管理画面で作成します。料金は各社からキーの持ち主へ請求されます。")
      }
    }
    .navigationTitle("プロバイダー")
    .memoraBackButton()
    .onAppear {
      savedKeys = Set(LLMProvider.allCases.filter { EngineAvailability.hasKey($0.keychainAccount) })
    }
  }
}
