import SwiftUI

struct RegisteredLLMEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var draft: RegisteredLLM
  @State private var showsKey = false
  @State private var saveError = false
  @State private var hasKey = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker(selection: $draft.provider) {
            ForEach(LLMProvider.allCases) { provider in
              Label(provider.label, image: provider.logoAssetName).tag(provider)
            }
          } label: {
            SettingsLabel("プロバイダー", icon: .cloud, color: .blue)
          }
          LabeledContent {
            TextField("例: 仕事用モデル", text: $draft.name)
              .multilineTextAlignment(.trailing)
          } label: {
            SettingsLabel("表示名", icon: .pencil, color: .purple)
          }
          LabeledContent {
            TextField("モデルID", text: $draft.modelID)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .multilineTextAlignment(.trailing)
          } label: {
            SettingsLabel("モデルID", icon: .cpu, color: .indigo)
          }
          Menu {
            ForEach(draft.provider.suggestedModels) { option in
              Button(option.name) {
                draft.modelID = option.id
                if draft.name.isEmpty { draft.name = option.name }
              }
            }
          } label: {
            SettingsLabel("候補から入力", icon: .listBulletRectangle, color: .gray)
          }
        } footer: {
          Text("表示名が入力欄の選択メニューに表示されます。APIにはモデルIDを送ります。")
        }
        Section {
          Button { showsKey = true } label: {
            SettingsLabel(hasKey ? "APIキーを変更" : "APIキーを設定", icon: .key, color: .orange)
          }
        } footer: {
          Text("キーはプロバイダーごとにKeychainへ保存します。手動でこのモデルを選ぶと、質問と対象の記録をこのプロバイダーへ送ります。")
        }
      }
      .navigationTitle("モデルを登録")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            if model.registeredLLMs.save(draft) { dismiss() } else { saveError = true }
          }
          .disabled(draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .sheet(isPresented: $showsKey) {
        APIKeySheet(llmProvider: draft.provider) { refreshKey() }
      }
      .onAppear(perform: refreshKey)
      .onChange(of: draft.provider) { _, _ in refreshKey() }
      .alert("保存できませんでした", isPresented: $saveError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("同じプロバイダーとモデルIDはすでに登録されています。既存のモデルを編集してください。")
      }
    }
  }

  private func refreshKey() {
    hasKey = EngineAvailability.hasKey(draft.provider.keychainAccount)
  }
}
