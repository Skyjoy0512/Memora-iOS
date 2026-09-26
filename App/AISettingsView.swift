import SwiftUI

struct AISettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isAPIKeySheetPresented = false
  @State private var availability = EngineAvailability.Status()
  @State private var hasKey = false

  var body: some View {
    Form {
      Section {
        ForEach(AIEngine.allCases) { option in
          engineRow(option)
        }
      } header: {
        Text("AIエンジン")
      } footer: {
        Text("端末内を優先し、必要な時だけクラウドを使います。選べない項目はこの版では利用できません。")
      }

      Section {
        NavigationLink {
          RegisteredLLMsView()
        } label: {
          SettingsLabel("登録済みモデル", icon: .cpu, color: .indigo)
        }
      } footer: {
        Text("Ask AIはAutoが基本です。入力欄から登録済みモデルを手動選択できます。")
      }

      if model.aiEngine.usesCloud {
        Section {
          NavigationLink {
            LLMProviderPickerView()
          } label: {
            HStack(spacing: 12) {
              ProviderLogo(provider: model.aiProvider, size: 29)
              LabeledContent("プロバイダー", value: model.aiProvider.label)
            }
          }

          NavigationLink {
            LLMModelPickerView()
          } label: {
            HStack(spacing: 12) {
              SettingsIcon(icon: .cpu, color: .indigo)
              LabeledContent("モデル", value: modelName)
            }
          }

          Button {
            isAPIKeySheetPresented = true
          } label: {
            HStack(spacing: 12) {
              SettingsIcon(icon: .keyFill, color: hasKey ? .green : .orange)
              LabeledContent("APIキー", value: hasKey ? "保存済み" : "未設定")
                .foregroundStyle(.primary)
            }
          }
        } header: {
          Text("クラウド（BYOK）")
        } footer: {
          Text("自分のAPIキーで各社のモデルを使います。キーはKeychainに保存し、設定画面にも再表示しません。記録の内容は、質問や要約のときだけ選んだプロバイダーへ送られます。")
        }
      }

      Section {
        LabeledContent { Text(effectiveLabel) } label: {
          SettingsLabel("実際に使う", icon: .sparkles, color: .purple)
        }
        LabeledContent { Text(availability.summary) } label: {
          SettingsLabel("この設定での状態", icon: .infoCircle, color: .gray)
        }
        if let message = availability.message {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("状態")
      }
    }
    .navigationTitle("AI整理")
    .memoraBackButton()
    .sheet(isPresented: $isAPIKeySheetPresented) {
      APIKeySheet(llmProvider: model.aiProvider) { refresh() }
    }
    .onAppear(perform: refresh)
    .onChange(of: model.aiEngine) { _, _ in refresh() }
    .onChange(of: model.aiProvider) { _, _ in refresh() }
  }

  private func engineRow(_ option: AIEngine) -> some View {
    Button {
      model.aiEngine = option
    } label: {
      HStack(spacing: 12) {
        SettingsIcon(icon: option.symbol, color: option.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text(option.label)
            .foregroundStyle(option.isSelectable ? .primary : .secondary)
          Text(option.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if option == model.aiEngine {
          Image(icon: .checkmark)
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
        }
      }
      .contentShape(Rectangle())
    }
    .disabled(!option.isSelectable)
    .accessibilityAddTraits(option == model.aiEngine ? .isSelected : [])
  }

  private var modelName: String {
    model.aiProvider.suggestedModels.first { $0.id == model.aiModelID }?.name ?? model.aiModelID
  }

  private func refresh() {
    hasKey = EngineAvailability.hasKey(model.aiProvider.keychainAccount)
    availability = EngineAvailability.ai(model.aiEngine, provider: model.aiProvider)
  }

  /// What will really run, including the model called for a cloud provider.
  private var effectiveLabel: String {
    let engine = AIEngineService.effectiveEngine(model.aiEngine)
    switch engine {
    case .cloud:
      return model.aiSelection.modelLabel
    case .automatic:
      return "利用できません（クラウドを選ぶと回答できます）"
    default:
      return engine.label
    }
  }
}
