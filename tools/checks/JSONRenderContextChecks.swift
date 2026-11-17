import Foundation

@main
struct JSONRenderContextChecks {
  static func expect(_ condition: @autoclosure () -> Bool, line: Int = #line) {
    guard condition() else { FileHandle.standardError.write(Data("JSONRenderContextChecks failed at \(line)\n".utf8)); exit(1) }
  }
  @MainActor static func main() {
    let model = MemoraModel()
    let original = Message(text: "本文")
    model.aiMessages = [original, Message(text: "続き")]
    model.aiHistory = [HistoryEntry(answer: original.text, sourceMessageID: original.id)]
    let fingerprint = JSONRenderSnapshot.fingerprint(original.text)
    let generation = model.aiWorkspaceGeneration, conversation = model.aiConversationID
    func accepted() -> Bool { model.acceptsJSONRenderInteraction(messageID: original.id, fingerprint: fingerprint, generation: generation, conversationID: conversation, workspaceID: nil) }
    expect(accepted())
    for change in ["generation", "conversation", "workspace", "protected", "restore", "thinking", "text", "role", "deleted"] {
      let fixture = model.aiMessages
      switch change {
      case "generation": model.aiWorkspaceGeneration = UUID()
      case "conversation": model.aiConversationID = UUID()
      case "workspace": model.currentTeamID = "foreign"
      case "protected": model.isStoreProtected = true
      case "restore": model.isRestoring = true
      case "thinking": model.aiMessages[0].isThinking = true
      case "text": model.aiMessages[0].text = "別の本文"
      case "role": model.aiMessages[0].role = .user
      default: model.aiMessages.removeFirst()
      }
      expect(!accepted())
      model.aiWorkspaceGeneration = generation; model.aiConversationID = conversation; model.currentTeamID = nil
      model.isStoreProtected = false; model.isRestoring = false; model.aiMessages = fixture
    }
    let body: [String: Any] = ["spec": ["root": "main", "elements": ["main": ["type": "Text", "props": ["text": "本文"], "children": []]]], "state": ["name": "入力"], "text": "表示本文"]
    model.saveJSONRenderSnapshot(body, messageID: original.id, fingerprint: fingerprint, generation: UUID(), conversationID: conversation, workspaceID: nil)
    expect(model.aiMessages[0].generatedUI == nil)
    model.saveJSONRenderSnapshot(body, messageID: original.id, fingerprint: fingerprint, generation: generation, conversationID: conversation, workspaceID: nil)
    expect(model.jsonRenderSnapshot(messageID: original.id, fingerprint: fingerprint)?.text == "表示本文")
    expect(model.aiHistory.first?.generatedUI == model.aiMessages[0].generatedUI)
    expect(model.historySaves == 1)
    var stale = model.aiHistory[0].generatedUI!
    stale.fingerprint = JSONRenderSnapshot.fingerprint("異なる回答")
    model.saveJSONRenderHistorySnapshot(stale, entryID: model.aiHistory[0].id)
    expect(model.historySaves == 1)
    expect(model.previousJSONRenderSpec(before: model.aiMessages[1].id)?["state"] is [String: Any])
    model.aiMessages[0].text = "変更された本文"
    expect(model.previousJSONRenderSpec(before: model.aiMessages[1].id) == nil)
    expect(model.stageJSONRenderQuestion("確認して送る質問"))
    expect(model.composerDraft == "確認して送る質問" && model.composerFocusRequest != nil)
    expect(!model.stageJSONRenderQuestion("既存の下書きを置換"))
    model.composerDraft = ""; model.composerAttachment = "file"; expect(!model.stageJSONRenderQuestion("質問"))
    model.composerAttachment = nil; model.composerDraftFailure = "unreadable"; expect(!model.stageJSONRenderQuestion("質問"))
    expect(JSONRenderActionRequest(body: ["id":"a","action":"deleteEverything","params":[:]]) == nil)
    expect(JSONRenderActionRequest(body: ["id":"a","action":"copyText","params":["text":"本文"]])?.action == .copyText)
    print("JSONRenderContextChecks: passed (production state/draft gates, nine stale-context cases, fingerprints, previous-spec revocation and typed bridge actions; model record shape is a fixture)")
  }
}

@MainActor final class MemoraModel {
  var aiWorkspaceGeneration = UUID()
  var aiConversationID = UUID()
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  var isAIChatResponding = false
  var aiMessages: [Message] = []
  var aiHistory: [HistoryEntry] = []
  var historySaves = 0
  func persistAIHistory() { historySaves += 1 }
  var composerDraftFailure: String?
  var composerDraft = ""
  var composerAttachment: String?
  var composerMentions: [String] = []
  var composerFocusRequest: UUID?
}
struct Message {
  enum Role { case user, assistant }
  var id = UUID()
  var text: String
  var role = Role.assistant
  var isThinking = false
  var generatedUI: JSONRenderSnapshot?
}

struct HistoryEntry {
  var id = UUID()
  var answer: String
  var sourceMessageID: UUID?
  var generatedUI: JSONRenderSnapshot?
}
