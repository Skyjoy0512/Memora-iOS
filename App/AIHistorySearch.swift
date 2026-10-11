import Foundation

enum AIHistorySearch {
  static func matching(_ entries: [AIConversationEntry], query: String) -> [AIConversationEntry] {
    let terms = normalized(query).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    guard !terms.isEmpty else { return entries }
    return entries.filter { entry in
      let text = normalized([entry.question, entry.answer, entry.scopeLabel].joined(separator: "\n"))
      return terms.allSatisfy { text.contains($0) }
    }
  }

  private static func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
  }
}
