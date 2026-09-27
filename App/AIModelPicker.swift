import SwiftUI

struct AIModelPicker: View {
  @Environment(MemoraModel.self) private var model
  @State private var showsModels = false
  @State private var readyProviders: Set<LLMProvider> = []

  var body: some View {
    Menu {
      Picker("モデル", selection: Binding(
        get: { model.registeredLLMs.selectedID },
        set: { model.registeredLLMs.select($0) }
      )) {
        Label("Auto", icon: .sparkles).tag(UUID?.none)
        ForEach(model.registeredLLMs.models) { registered in
          Label {
            Text(readyProviders.contains(registered.provider)
                 ? registered.name : "\(registered.name)（APIキー未設定）")
          } icon: {
            Image(registered.provider.logoAssetName)
          }
          .tag(Optional(registered.id))
          .disabled(!readyProviders.contains(registered.provider))
        }
      }
      Button("モデルを登録・編集", icon: .sliderHorizontal3) { showsModels = true }
    } label: {
      HStack(spacing: 6) {
        if let registered = model.registeredLLMs.selectedModel {
          ProviderLogo(provider: registered.provider, size: 20)
        } else {
          Image(icon: .sparkles).font(.subheadline)
        }
        Text(model.askAIModelName)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
          .truncationMode(.tail)
        Image(icon: .chevronDown)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.primary)
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 6)
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    }
    .accessibilityLabel("モデルを選択")
    .accessibilityValue(model.askAIModelName)
    .sheet(isPresented: $showsModels, onDismiss: refreshKeys) {
      NavigationStack {
        RegisteredLLMsView()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              ToolbarIconButton("閉じる", icon: .xmark) { showsModels = false }
            }
          }
      }
    }
    .onAppear(perform: refreshKeys)
    .onChange(of: model.isSettingsPresented) { _, presented in
      if !presented { refreshKeys() }
    }
  }

  private func refreshKeys() {
    readyProviders = Set(LLMProvider.allCases.filter { EngineAvailability.hasKey($0.keychainAccount) })
  }
}
