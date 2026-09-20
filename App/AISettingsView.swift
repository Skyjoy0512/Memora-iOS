import SwiftUI

struct AISettingsView: View {
  @AppStorage("memora.aiEngine") private var engine = AIEngine.automatic
  @AppStorage("memora.aiProvider") private var provider = CloudProvider.openAI
  @State private var isAPIKeySheetPresented = false

  var body: some View {
    Form {
      Section {
        Picker("エンジン", selection: $engine) {
          ForEach(AIEngine.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        Text(engine.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
      } header: {
        Text("AIエンジン")
      } footer: {
        Text("端末内を優先し、必要な時だけクラウドを使います。")
      }

      if engine.usesCloud {
        Section {
          Picker("プロバイダー", selection: $provider) {
            ForEach(CloudProvider.allCases.filter(\.supportsAI)) { option in
              Text(option.label).tag(option)
            }
          }
          Button("APIキーを設定", systemImage: "key") {
            isAPIKeySheetPresented = true
          }
        } header: {
          Text("クラウド（BYOK）")
        } footer: {
          Text("シークレットはKeychainに保存し、設定画面にも再表示しません。")
        }
      }
    }
    .navigationTitle("AI整理")
    .memoraBackButton()
    .sheet(isPresented: $isAPIKeySheetPresented) {
      APIKeySheet(provider: provider.label, account: "ai.\(provider.rawValue)")
    }
    .onAppear {
      if !provider.supportsAI {
        provider = .openAI
      }
    }
  }
}
