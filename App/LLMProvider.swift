import Foundation

/// A bring-your-own-key language model provider for Ask AI and summaries.
/// Raw values are stored in settings; `openAI` and `anthropic` match the names
/// saved before more providers were added, so an existing choice and its key
/// carry over.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
  case anthropic
  case openAI
  case google
  case deepSeek
  case moonshot
  case xAI
  case mistral
  case qwen
  case openRouter

  static var defaultCloudProvider: Self { .deepSeek }

  /// New setups use DeepSeek. A saved selection or an older explicit OpenAI
  /// model/key remains authoritative; upgrading must not switch its destination.
  static func restored(_ savedValue: String?, hasLegacyOpenAIConfiguration: Bool) -> Self {
    if let savedValue, let provider = Self(rawValue: savedValue) { return provider }
    return hasLegacyOpenAIConfiguration ? .openAI : defaultCloudProvider
  }

  var id: Self { self }

  /// The name people know the models by.
  var label: String {
    switch self {
    case .anthropic: "Claude"
    case .openAI: "OpenAI"
    case .google: "Gemini"
    case .deepSeek: "DeepSeek"
    case .moonshot: "Kimi"
    case .xAI: "Grok"
    case .mistral: "Mistral"
    case .qwen: "Qwen"
    case .openRouter: "OpenRouter"
    }
  }

  /// Who issues the key, so the person knows which console to open.
  var company: String {
    switch self {
    case .anthropic: "Anthropic"
    case .openAI: "OpenAI"
    case .google: "Google AI Studio"
    case .deepSeek: "DeepSeek"
    case .moonshot: "Moonshot AI"
    case .xAI: "xAI"
    case .mistral: "Mistral AI"
    case .qwen: "Alibaba Cloud Model Studio"
    case .openRouter: "OpenRouter"
    }
  }

  var logoAssetName: String {
    switch self {
    case .anthropic: "provider.anthropic"
    case .openAI: "provider.openai"
    case .google: "provider.google"
    case .deepSeek: "provider.deepseek"
    case .moonshot: "provider.moonshot"
    case .xAI: "provider.xai"
    case .mistral: "provider.mistral"
    case .qwen: "provider.qwen"
    case .openRouter: "provider.openrouter"
    }
  }

  /// Anthropic has its own Messages API; every other provider here accepts the
  /// OpenAI chat-completions shape at its own address.
  var usesAnthropicAPI: Bool { self == .anthropic }

  var baseURL: URL {
    let string = switch self {
    case .anthropic: "https://api.anthropic.com/v1"
    case .openAI: "https://api.openai.com/v1"
    case .google: "https://generativelanguage.googleapis.com/v1beta/openai"
    case .deepSeek: "https://api.deepseek.com"
    case .moonshot: "https://api.moonshot.ai/v1"
    case .xAI: "https://api.x.ai/v1"
    case .mistral: "https://api.mistral.ai/v1"
    case .qwen: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    case .openRouter: "https://openrouter.ai/api/v1"
    }
    return URL(string: string)!
  }

  /// Where the person creates a key.
  var keyConsoleURL: URL {
    let string = switch self {
    case .anthropic: "https://console.anthropic.com/settings/keys"
    case .openAI: "https://platform.openai.com/api-keys"
    case .google: "https://aistudio.google.com/apikey"
    case .deepSeek: "https://platform.deepseek.com/api_keys"
    case .moonshot: "https://platform.moonshot.ai/console/api-keys"
    case .xAI: "https://console.x.ai"
    case .mistral: "https://console.mistral.ai/api-keys"
    case .qwen: "https://modelstudio.console.alibabacloud.com"
    case .openRouter: "https://openrouter.ai/keys"
    }
    return URL(string: string)!
  }

  /// A hint of what a key looks like, shown in the empty field.
  var keyPlaceholder: String {
    switch self {
    case .anthropic: "sk-ant-…"
    case .openAI, .deepSeek, .moonshot, .qwen: "sk-…"
    case .google: "AIza…"
    case .xAI: "xai-…"
    case .mistral: "APIキー"
    case .openRouter: "sk-or-…"
    }
  }

  /// A caveat worth knowing before choosing, if any.
  var note: String? {
    switch self {
    case .moonshot: "国際版（platform.moonshot.ai）のキーを使います。"
    case .qwen: "Model Studio 国際版（シンガポール）のキーを使います。"
    case .openRouter: "1つのキーで各社のモデルを切り替えて使えます。"
    default: nil
    }
  }

  /// The Keychain entry holding this provider's key.
  var keychainAccount: String { "ai.\(rawValue)" }

  /// Suggested models, most useful first. Providers rename models often, so
  /// the settings screen can also load the live list with the saved key.
  var suggestedModels: [LLMModelOption] {
    switch self {
    case .anthropic:
      [
        LLMModelOption(id: "claude-opus-5", name: "Claude Opus 5", detail: "高性能・おすすめ"),
        LLMModelOption(id: "claude-sonnet-5", name: "Claude Sonnet 5", detail: "速さと性能のバランス"),
        LLMModelOption(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", detail: "高速・低価格"),
        LLMModelOption(id: "claude-fable-5-1", name: "Claude Fable 5.1", detail: "最上位・時間がかかります")
      ]
    case .openAI:
      [
        LLMModelOption(id: "gpt-6-sol", name: "GPT-6 Sol", detail: "速さと性能のバランス"),
        LLMModelOption(id: "gpt-6-luna", name: "GPT-6 Luna", detail: "高速・低価格"),
        LLMModelOption(id: "gpt-6-astra", name: "GPT-6 Astra", detail: "最上位")
      ]
    case .google:
      [
        LLMModelOption(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", detail: "高速・おすすめ"),
        LLMModelOption(id: "gemini-3.1-pro", name: "Gemini 3.1 Pro", detail: "高性能"),
        LLMModelOption(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", detail: "低価格")
      ]
    case .deepSeek:
      [
        LLMModelOption(id: "deepseek-flash", name: "DeepSeek Flash", detail: "高速・低価格"),
        LLMModelOption(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", detail: "高性能")
      ]
    case .moonshot:
      [
        LLMModelOption(id: "kimi-k2.6", name: "Kimi K2.6", detail: "汎用"),
        LLMModelOption(id: "kimi-k3", name: "Kimi K3", detail: "最上位・長文")
      ]
    case .xAI:
      [
        LLMModelOption(id: "grok-4.7", name: "Grok 4.7", detail: "最新")
      ]
    case .mistral:
      [
        LLMModelOption(id: "mistral-medium-latest", name: "Mistral Medium", detail: "バランス"),
        LLMModelOption(id: "mistral-large-latest", name: "Mistral Large", detail: "高性能"),
        LLMModelOption(id: "mistral-small-latest", name: "Mistral Small", detail: "高速・低価格")
      ]
    case .qwen:
      [
        LLMModelOption(id: "qwen-plus", name: "Qwen Plus", detail: "バランス"),
        LLMModelOption(id: "qwen3-max", name: "Qwen3 Max", detail: "高性能"),
        LLMModelOption(id: "qwen-flash", name: "Qwen Flash", detail: "高速・低価格")
      ]
    case .openRouter:
      [
        LLMModelOption(id: "openrouter/auto", name: "自動で選ぶ", detail: "質問に合うモデルをOpenRouterが選択"),
        LLMModelOption(id: "anthropic/claude-sonnet-5", name: "Claude Sonnet 5", detail: "Anthropic"),
        LLMModelOption(id: "deepseek/deepseek-v4-pro", name: "DeepSeek V4 Pro", detail: "DeepSeek"),
        LLMModelOption(id: "moonshotai/kimi-k2.6", name: "Kimi K2.6", detail: "Moonshot AI")
      ]
    }
  }

  var defaultModelID: String {
    suggestedModels.first?.id ?? ""
  }
}
