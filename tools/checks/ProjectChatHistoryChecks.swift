import Foundation

@main
struct ProjectChatHistoryChecks {
  static func main() throws {
    let target = ProjectCitation.Target.source(UUID())
    let evidence = ProjectCitation(target: target, title: "旅程", excerpt: "箱根")
    let messages = (0..<6).flatMap { index in
      [ProjectChatTurn(role: .user, text: "質問\(index)"),
       ProjectChatTurn(role: .assistant, text: "回答\(index)", contextReferences: [evidence])]
    }
    let history = ProjectChatHistory.text(messages, allowed: [target], budget: 10_000)
    precondition(!history.contains("質問0") && !history.contains("質問1"))
    precondition(history.contains("質問2") && history.contains("回答5"))
    for budget in [0, 10, 30, 100] {
      let limited = ProjectChatHistory.text(messages, allowed: [target], budget: budget)
      precondition(limited.count <= budget)
      precondition(limited.components(separatedBy: "ユーザー:").count == limited.components(separatedBy: "AI:").count)
    }
    precondition(ProjectChatHistory.text(messages, allowed: [], budget: 10_000).isEmpty)
    var thread = ProjectChatThread(projectID: UUID(), title: "旅程", messages: messages)
    let data = try JSONEncoder().encode(thread)
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    legacy.removeValue(forKey: "pendingMessageID")
    legacy.removeValue(forKey: "lastFailure")
    let decoded = try JSONDecoder().decode(ProjectChatThread.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(decoded == thread)
    thread.projectID = nil
    let archived = try JSONDecoder().decode(ProjectChatThread.self, from: JSONEncoder().encode(thread))
    precondition(archived.projectID == nil && archived.messages == messages)
    print("ProjectChatHistoryChecks: passed (bounded complete turns, revoked evidence, legacy decoding, retained archive)")
  }
}
