import SwiftUI

struct AISettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isAPIKeySheetPresented = false
  @State private var availability = EngineAvailability.Status()
  @State private var hasKey = false
  @State private var readyProviders: Set<LLMProvider> = []

  var body: some View {
    MemoraForm {
      Section("使用中のAI") {
        VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
          Text(effectiveLabel).font(MemoraTypography.body.weight(.medium))
          Text(usesEffectiveCloud ? model.askAIConfiguration.llm.summaryDestination : "このiPhoneで処理")
            .font(MemoraTypography.metadata).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.ai.effective")
        LabeledContent("状態", value: availability.summary)
        if let message = availability.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
      }
      Section {
        Picker("標準のAI", selection: Binding(get: { model.aiEngine }, set: { model.aiEngine = $0 })) {
          ForEach(AIEngine.allCases) { option in
            Text(option.isSelectable ? option.label : "\(option.label)（準備中）")
              .tag(option).disabled(!option.isSelectable)
          }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("settings.ai.engine")
      } footer: {
        Text(model.registeredLLMs.selectedModel == nil
          ? "下で登録済みモデルを指定すると、そのモデルを使います。"
          : "現在は登録済みモデルを使用中です。標準のAIの変更は、モデルの指定を解除すると反映されます。")
      }

      Section {
        Picker(selection: Binding(
          get: { model.registeredLLMs.selectedID },
          set: { model.registeredLLMs.select($0) }
        )) {
          Text("指定なし・標準のAIを使う").tag(UUID?.none)
          ForEach(model.registeredLLMs.models) { registered in
            Text(readyProviders.contains(registered.provider)
                 ? registered.name : "\(registered.name)（APIキー未設定）")
              .tag(Optional(registered.id))
              .disabled(!readyProviders.contains(registered.provider))
          }
        } label: {
          SettingsLabel("登録済みモデルを指定", icon: .sparkles)
        }
        .pickerStyle(.menu)

        NavigationLink {
          RegisteredLLMsView()
        } label: {
          SettingsLabel("モデルを追加・管理", icon: .cpu)
        }
      }

      if model.aiEngine.usesCloud && model.registeredLLMs.selectedModel == nil {
        Section {
          NavigationLink {
            LLMProviderPickerView()
          } label: {
            HStack(spacing: 12) {
              SettingsIcon(icon: .sparkles)
              LabeledContent("サービス", value: model.aiProvider.label)
            }
          }

          NavigationLink {
            LLMModelPickerView()
          } label: {
            HStack(spacing: 12) {
              SettingsIcon(icon: .cpu)
              LabeledContent("モデル", value: modelName)
            }
          }

          Button {
            isAPIKeySheetPresented = true
          } label: {
            HStack(spacing: 12) {
              SettingsIcon(icon: .keyFill)
              LabeledContent("APIキー", value: hasKey ? "保存済み" : "未設定")
                .foregroundStyle(.primary)
            }
          }
        } header: {
          Text("クラウドAI")
        }
      }

      Section {
        DisclosureGroup("詳細設定") {
          NavigationLink("モデルの上限") { ModelCapabilitiesView() }
          NavigationLink("Web検索・調査") { WebResearchSettingsView() }

        }
      }

    }
    .navigationTitle("AIモデル")
    .memoraBackButton()
    .sheet(isPresented: $isAPIKeySheetPresented) {
      APIKeySheet(llmProvider: model.aiProvider) { refresh() }
    }
    .onAppear(perform: refresh)
    .onChange(of: model.aiEngine) { _, _ in refresh() }
    .onChange(of: model.aiProvider) { _, _ in refresh() }
    .onChange(of: model.registeredLLMs.revision) { _, _ in refresh() }
  }

  private var modelName: String {
    model.aiProvider.suggestedModels.first { $0.id == model.aiModelID }?.name ?? model.aiModelID
  }

  private func refresh() {
    hasKey = EngineAvailability.hasKey(model.aiProvider.keychainAccount)
    let configuration = model.askAIConfiguration
    availability = EngineAvailability.ai(configuration.llm.isMemoraIntelligence ? .memora : configuration.engine,
      provider: configuration.llm.provider)
    readyProviders = Set(LLMProvider.allCases.filter { EngineAvailability.hasKey($0.keychainAccount) })
  }

  private var usesEffectiveCloud: Bool {
    AIEngineService.effectiveEngine(model.askAIConfiguration.engine) == .cloud
  }

  private var effectiveLabel: String {
    if let registered = model.registeredLLMs.selectedModel { return registered.name }
    let configuration = model.askAIConfiguration
    if AIEngineService.effectiveEngine(configuration.engine) == .cloud {
      return configuration.llm.isMemoraIntelligence ? "Memora Intelligence" : configuration.llm.modelLabel
    }
    return configuration.engine.label
  }
}
