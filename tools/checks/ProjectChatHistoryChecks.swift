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
    let history = ProjectChatHistory.context(messages, budget: 10_000)
    precondition(!history.text.contains("質問0") && !history.text.contains("質問1"))
    precondition(history.text.contains("質問2") && history.text.contains("回答5"))
    precondition(history.references == [evidence])
    for budget in [0, 10, 30, 100] {
      let limited = ProjectChatHistory.context(messages, budget: budget)
      precondition(limited.text.count <= budget)
      precondition(limited.text.components(separatedBy: "ユーザー:").count == limited.text.components(separatedBy: "AI:").count)
    }
    var rejected = messages[1]
    rejected.contextReferences = []
    let unauthorized = ProjectChatHistory.context([messages[0], rejected], budget: 10_000)
    precondition(unauthorized.text.isEmpty && unauthorized.references.isEmpty)
    precondition(ProjectChatHistory.referencesForReplay(messages[1], cloud: true).isEmpty)
    precondition(ProjectChatHistory.referencesForReplay(messages[1], cloud: false) == [evidence])
    var authorized = messages[1]
    authorized.cloudReplayAuthorizationVersion = 1
    precondition(ProjectChatHistory.referencesForReplay(authorized, cloud: true) == [evidence])
    var photo = evidence
    photo.photo = .init(name: "private.jpg", byteCount: 1_024, modifiedAt: .now, textReadAt: .now)
    authorized.contextReferences = [evidence, photo]
    precondition(ProjectChatHistory.referencesForReplay(authorized, cloud: true).isEmpty)
    let restored = ProjectChatThread(title: "復元した会話", messages: [authorized]).withoutCloudReplayAuthorization
    precondition(restored.messages[0].cloudReplayAuthorizationVersion == nil)
    precondition(restored.messages[0].text == authorized.text && restored.messages[0].contextReferences == [evidence, photo])
    var omitted = messages[1]
    omitted.contextReferences = (0..<65).map { index in
      ProjectCitation(target: target, title: "出典", excerpt: "根拠\(index)")
    }
    let oversized = ProjectChatHistory.context([messages[0], omitted], budget: 10_000)
    precondition(oversized.text.isEmpty && oversized.references.isEmpty)
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
