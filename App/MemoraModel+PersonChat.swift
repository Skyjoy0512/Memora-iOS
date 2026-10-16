import Foundation

extension MemoraModel {
  func beginPersonConversation(_ personID: UUID) {
    guard person(id: personID) != nil else { return }
    startNewAIChat()
    aiPersonScopeID = personID
    selectedTab = .askAI
    persistActiveAIConversation()
    _ = sendPersonChat("この人との最近の会話、関連する会議の決定、未完了の約束を根拠付きでまとめて", personID: personID)
  }

  @discardableResult
  func sendPersonChat(_ question: String, personID: UUID) -> Bool {
    guard aiPersonScopeID == personID, person(id: personID) != nil else {
      aiRequestRefusalMessage = "人物が削除されました。新しいチャットを開いてください。"
      return false
    }
    let recordIDs = Set(meetings(withPerson: personID).map(\.id))
    let tools: [AgentTool] = [.readPerson, .searchRecords, .readRecord, .listTasks, .askUser, .draftEmail, .createDocument, .createSlides]
    let policy = AIPluginExecutionPolicy(pluginIDs: ["person:" + personID.uuidString],
      toolIDs: Set(tools.map { "memora:" + $0.rawValue }), recordIDs: recordIDs,
      limitsRecordReads: true, personID: personID)
    return sendAgentChat(question, pluginPolicy: policy)
  }
}
