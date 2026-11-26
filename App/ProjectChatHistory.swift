import Foundation

enum ProjectChatHistory {
  struct Context {
    var text: String
    var references: [ProjectCitation]
  }

  static func referencesForReplay(_ turn: ProjectChatTurn, cloud: Bool) -> [ProjectCitation] {
    let references = turn.contextReferences ?? turn.citations
    guard !cloud || (turn.cloudReplayAuthorizationVersion == 1 && references.allSatisfy { $0.photo == nil }) else { return [] }
    return references
  }

  static func context(_ messages: [ProjectChatTurn], budget: Int) -> Context {
    var pairs: [Context] = []
    var question: String?
    for message in messages {
      if message.role == .user { question = message.text; continue }
      guard let prompt = question else { continue }
      let references = message.contextReferences ?? message.citations
      guard !references.isEmpty else {
        question = nil
        continue
      }
      pairs.append(Context(text: "ユーザー: \(prompt)\nAI: \(message.text)\n", references: references))
      question = nil
    }
    var result = ""
    var retained: [ProjectCitation] = []
    var seen = Set<ProjectCitation>()
    for pair in pairs.suffix(4).reversed() {
      guard pair.text.count + result.count <= budget, seen.union(pair.references).count <= 64 else { break }
      result = pair.text + result
      retained += pair.references.filter { seen.insert($0).inserted }
    }
    return Context(text: result, references: retained)
  }
}
