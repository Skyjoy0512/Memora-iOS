import SwiftUI

/// The real context a selected model is given, and a place to correct it for a
/// custom endpoint or a model whose published limits changed. Values are stored
/// locally; nothing here contacts a provider.
struct ModelCapabilitiesView: View {
  @Environment(MemoraModel.self) private var model
  @State private var contextText = ""
  @State private var outputText = ""
  @State private var requestText = ""
  @State private var saved = false

  private var llm: LLMSelection { model.askAIConfiguration.llm }
  private var capabilities: ModelCapabilities { ModelCapabilities.resolve(llm: llm) }
  private var overrideKey: String { ModelCapabilityOverrides.key(provider: llm.provider, modelID: llm.modelID) }

  var body: some View {
    MemoraForm {
      Section {
        labeled("モデル", llm.modelLabel)
        labeled("コンテキスト", "\(capabilities.contextWindowTokens.formatted()) tokens")
        labeled("最大出力", "\(capabilities.maximumOutputTokens.formatted()) tokens")
        labeled("リクエスト上限", ByteCountFormatter.string(fromByteCount: Int64(capabilities.maximumRequestBytes), countStyle: .file))
        labeled("取得元", sourceLabel(capabilities.source))
      } header: {
        Text("選択中のモデル")
      } footer: {
        Text(capabilities.note ?? "アプリが宣言した上限です。提供元での確認結果ではありません。")
      }

      Section {
        numberField("コンテキスト（tokens）", text: $contextText)
        numberField("最大出力（tokens）", text: $outputText)
        numberField("リクエスト上限（bytes）", text: $requestText)
        Button("このモデルに適用") { apply() }
          .disabled(contextText.isEmpty && outputText.isEmpty && requestText.isEmpty)
        Button("既定に戻す", role: .destructive) { reset() }
          .disabled(!ModelCapabilityOverrides.stored().keys.contains(overrideKey))
        if saved { Text("保存しました。次の依頼から使います。").foregroundStyle(.secondary) }
      } header: {
        Text("上限を調整")
      } footer: {
        Text("不明なモデルやOpenAI互換の独自エンドポイントは安全側の値で動きます。値を上げても、コンテキスト・出力・リクエストの各上限は有限のままです。料金の確認できないモデルでは推定費用を表示しません。")
      }
    }
    .navigationTitle("モデルの上限")
    .onAppear(perform: load)
  }

  private func labeled(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
    }
  }

  private func numberField(_ title: String, text: Binding<String>) -> some View {
    TextField(title, text: text)
      .keyboardType(.numberPad)
      .multilineTextAlignment(.trailing)
  }

  private func load() {
    if let override = ModelCapabilityOverrides.stored()[overrideKey] {
      contextText = override.contextWindowTokens.map(String.init) ?? ""
      outputText = override.maximumOutputTokens.map(String.init) ?? ""
      requestText = override.maximumRequestBytes.map(String.init) ?? ""
    } else {
      contextText = String(capabilities.contextWindowTokens)
      outputText = String(capabilities.maximumOutputTokens)
      requestText = String(capabilities.maximumRequestBytes)
    }
  }

  private func apply() {
    var overrides = ModelCapabilityOverrides.stored()
    let override = ModelCapabilityOverride(
      contextWindowTokens: Int(contextText),
      maximumOutputTokens: Int(outputText),
      maximumRequestBytes: Int(requestText))
    guard override.applying(to: ModelCapabilities.conservative(provider: llm.provider, modelID: llm.modelID)) != nil else {
      saved = false
      return
    }
    overrides[overrideKey] = override
    ModelCapabilityOverrides.save(overrides)
    saved = true
    load()
  }

  private func reset() {
    var overrides = ModelCapabilityOverrides.stored()
    overrides.removeValue(forKey: overrideKey)
    ModelCapabilityOverrides.save(overrides)
    saved = true
    load()
  }

  private func sourceLabel(_ source: ModelCapabilities.Source) -> String {
    switch source {
    case .declared: "アプリの宣言（未検証）"
    case .providerAPI: "提供元APIで確認"
    case .userOverride: "利用者の設定"
    case .conservative: "安全側の既定値"
    }
  }
}
