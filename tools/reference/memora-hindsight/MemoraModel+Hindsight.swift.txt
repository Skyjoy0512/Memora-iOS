import Foundation

// Hindsight (github.com/vectorize-io/hindsight) as Ask AI's long-term memory:
// what the person asked and was told is retained, and what bears on a new
// question is recalled into the prompt before the model answers. Its own
// setting, apart from the on-device memories in `MemoraModel+Memory`.
extension MemoraModel {
  /// The memories Hindsight holds that bear on a question, as one prompt block,
  /// within `budget` characters. Empty when it is off or the server cannot be
  /// reached: a memory that is not there must never stop an answer.
  func hindsightContext(for question: String, budget: Int) async -> String {
    let config = hindsightConfig
    guard config.isEnabled, config.isConfigured, budget > 80 else { return "" }
    let token = KeychainStore.string(forKey: HindsightConfig.tokenAccount)
    guard let memories = try? await HindsightClient.recall(query: question, config: config, token: token),
          !memories.isEmpty else {
      return ""
    }

    var lines = ["Hindsightに蓄積された利用者の記憶（参考。事実として扱い、無いことは推測しない）:"]
    var used = lines[0].count
    for memory in memories {
      let line = "- \(memory)"
      guard used + line.count + 1 <= budget else { break }
      lines.append(line)
      used += line.count + 1
    }
    return lines.count > 1 ? lines.joined(separator: "\n") : ""
  }

  /// Stores one finished exchange so Hindsight can extract what it should
  /// remember. Sent in the background; a failure is never surfaced.
  func retainHindsight(question: String, answer: String) {
    let config = hindsightConfig
    guard config.isEnabled, config.isConfigured else { return }
    let token = KeychainStore.string(forKey: HindsightConfig.tokenAccount)
    let content = "利用者: \(question)\n回答: \(answer)"
    Task {
      try? await HindsightClient.retain(
        content: content,
        context: "MemoraのAsk AIとの会話",
        config: config,
        token: token
      )
    }
  }
}
