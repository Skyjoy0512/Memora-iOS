import Foundation

enum ProjectChatHistory {
  static func text(_ messages: [ProjectChatTurn], allowed: Set<ProjectCitation.Target>, budget: Int) -> String {
    var pairs: [String] = []
    var question: String?
    for message in messages {
      if message.role == .user { question = message.text; continue }
      guard let prompt = question else { continue }
      let references = message.contextReferences ?? message.citations
      guard !references.isEmpty, references.allSatisfy({ allowed.contains($0.target) }) else {
        question = nil
        continue
      }
      pairs.append("ユーザー: \(prompt)\nAI: \(message.text)\n")
      question = nil
    }
    var result = ""
    for pair in pairs.suffix(4).reversed() {
      guard pair.count + result.count <= budget else { break }
      result = pair + result
    }
    return result
  }

}
