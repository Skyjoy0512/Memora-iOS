import Foundation

/// How much room a request needs. The task changes the target, the model caps it.
enum ContextTaskKind: String, Codable, Sendable, CaseIterable {
  case chat
  case agent
  case deepAnalysis
  case presentation
  case research

  /// The aim before the model's own window is applied. These are goals, not
  /// guarantees: a smaller model receives its safe share instead.
  var inputTokenTarget: Int {
    switch self {
    case .chat: 64_000
    case .agent: 96_000
    case .deepAnalysis: 256_000
    case .presentation: 192_000
    case .research: 1_000_000
    }
  }

  var outputTokenTarget: Int {
    switch self {
    case .chat: 4_096
    case .agent: 16_000
    case .deepAnalysis: 24_000
    case .presentation: 32_000
    case .research: 16_000
    }
  }

  var isDeep: Bool { self == .deepAnalysis || self == .presentation || self == .research }

  var label: String {
    switch self {
    case .chat: "通常の質問"
    case .agent: "エージェント"
    case .deepAnalysis: "深い分析"
    case .presentation: "資料作成"
    case .research: "調査"
    }
  }
}

/// One request's token plan. `inputTokens` is what is left after the answer's
/// reservation and a safety margin; `inputCharacterBudget` is a deliberately
/// conservative character ceiling for that many tokens.
struct TokenBudget: Hashable, Sendable {
  var capabilities: ModelCapabilities
  var task: ContextTaskKind
  var contextWindowTokens: Int
  var outputTokens: Int
  var safetyTokens: Int
  var inputTokens: Int

  /// Japanese can approach one token per character, so one character per token
  /// is used as the ceiling. English will not fill the window, which is the
  /// safe direction. The number never exceeds the model's real input room.
  var inputCharacterBudget: Int { inputTokens }

  var estimatedCostUSD: Double? {
    guard let input = capabilities.inputPricePerMillionTokens,
          let output = capabilities.outputPricePerMillionTokens else { return nil }
    return Double(inputTokens) / 1_000_000 * input + Double(outputTokens) / 1_000_000 * output
  }
}

enum TokenBudgetManager {
  /// A safety margin for tokenizer drift, the tool schema and the provider's
  /// own counting. It grows with the window but never exceeds a quarter.
  static func safetyTokens(contextWindow: Int) -> Int {
    min(max(1_024, contextWindow / 50), contextWindow / 4)
  }

  static func budget(capabilities: ModelCapabilities, task: ContextTaskKind) -> TokenBudget {
    let window = max(1_024, capabilities.contextWindowTokens)
    let requestedOutput = min(max(512, task.outputTokenTarget), max(512, capabilities.maximumOutputTokens))
    let safety = safetyTokens(contextWindow: window)
    // Never reserve so much for the answer that the input has no room.
    let output = min(requestedOutput, max(256, window - safety - 1_024))
    let input = max(0, window - output - safety)
    return TokenBudget(capabilities: capabilities, task: task, contextWindowTokens: window,
      outputTokens: output, safetyTokens: safety,
      inputTokens: min(input, task.inputTokenTarget))
  }

  /// Kept as the public name used by callers; the estimate lives in one place.
  static func estimatedTokens(_ text: String) -> Int {
    TokenEstimate.tokens(text)
  }
}

/// Whether a request asks for the work that justifies a deep pass over the
/// person's records. A short factual question stays on the cheap path.
enum DeepContextPolicy {
  private static let presentationTerms = [
    "powerpoint", "pptx", "スライド", "資料を作", "資料作成", "提案書", "経営報告", "事業計画",
    "報告資料", "営業資料", "プレゼン", "講演資料", "説明資料", "ピッチ"
  ]
  private static let deepTerms = [
    "deep research", "ディープリサーチ", "深掘り", "経緯", "背景", "これまでの決定", "意思決定",
    "全体を分析", "長期", "横断", "比較分析", "原因を分析", "振り返り", "統合して"
  ]

  static func task(for request: String) -> ContextTaskKind {
    let text = request.lowercased()
    if presentationTerms.contains(where: { text.contains($0) }) { return .presentation }
    if text.contains("deep research") || text.contains("ディープリサーチ") { return .research }
    if deepTerms.contains(where: { text.contains($0) }) { return .deepAnalysis }
    return .agent
  }

  static func isDeep(_ request: String) -> Bool {
    task(for: request).isDeep
  }
}
