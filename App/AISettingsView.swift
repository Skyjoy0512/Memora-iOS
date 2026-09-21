import SwiftUI

struct AISettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isAPIKeySheetPresented = false

  var body: some View {
    @Bindable var model = model

    return Form {
      Section {
        Picker("エンジン", selection: $model.aiEngine) {
          ForEach(AIEngine.allCases) { option in
            Text(option.label)
              .tag(option)
              .disabled(!option.isSelectable)
          }
        }
        LabeledContent("実際に使う", value: effectiveLabel)
        Text(model.aiEngine.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
      } header: {
        Text("AIエンジン")
      } footer: {
        Text("端末内を優先し、必要な時だけクラウドを使います。選べない項目はこの版では利用できません。")
      }

      if model.aiEngine.usesCloud {
        Section {
          Picker("プロバイダー", selection: $model.aiProvider) {
            ForEach(CloudProvider.allCases) { option in
              Text(option.label)
                .tag(option)
                .disabled(!option.supportsAI)
            }
          }
          Button("APIキーを設定", systemImage: "key") {
            isAPIKeySheetPresented = true
          }
        } header: {
          Text("クラウド（BYOK）")
        } footer: {
          Text("回答に使えるのは OpenAI と Anthropic です。シークレットはKeychainに保存し、設定画面にも再表示しません。")
        }
      }
    }
    .navigationTitle("AI整理")
    .memoraBackButton()
    .sheet(isPresented: $isAPIKeySheetPresented) {
      APIKeySheet(provider: model.aiProvider.label, account: "ai.\(model.aiProvider.rawValue)")
    }
    .onAppear {
      if !model.aiProvider.supportsAI {
        model.aiProvider = .openAI
      }
    }
  }

  /// What will really run, including the model called for a cloud provider.
  private var effectiveLabel: String {
    let engine = AIEngineService.effectiveEngine(model.aiEngine)
    switch engine {
    case .cloud:
      return "\(model.aiProvider.label) · \(model.aiProvider.aiModelName)"
    case .automatic:
      return "利用できません（クラウドを選ぶと回答できます）"
    default:
      return engine.label
    }
  }
}
