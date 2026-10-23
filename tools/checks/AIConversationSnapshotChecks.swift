import Foundation

@main
enum AIConversationSnapshotChecks {
  static func main() throws {
    var answer = AIChatMessage(role: .assistant, text: "資料の回答【資料1】")
    let recordID = UUID()
    answer.sources = [AIChatSource(meetingID: recordID, title: "資料", excerpts: [.init(text: "根拠", start: 12)])]
    answer.details = AIAnswerDetails(scopeLabel: "すべて", engineLabel: "端末内", sourceCount: 1, generatedAt: .now)
    answer.interfaceTaskIDs = [UUID()]
    answer.interfaceProjectIDs = [UUID()]
    answer.interfaceWorkspaceID = "private-team"
    let externalGrant = UUID()
    answer.mcpResultAuthorizationIDs = [externalGrant]
    answer.calendarReadSnapshot = AICalendarReadSnapshot(revision: UUID(), readAt: .now, events: [
      .init(sourceID: "never-persist-eventkit-id", title: "取得した予定", start: .now, end: .now, isAllDay: false)
    ])
    answer.cloudAuthorizationTargets = [.meeting(recordID)]
    answer.artifactProvenance = ArtifactProvenance(workspaceID: nil, sourceMessageID: answer.id,
      records: [.init(target: .task(recordID), fingerprint: String(repeating: "a", count: 64))])
    var resident = AIChatMessage(role: .assistant, text: "朝のブリーフ")
    resident.residentName = "朝"
    resident.residentAgentID = UUID()
    resident.residentSymbol = .sparkles
    resident.suggestions = ["タスクを確認"]
    var unfinishedResident = resident
    unfinishedResident.id = UUID()
    unfinishedResident.isThinking = true
    let snapshot = AIConversationSnapshot(messages: [.init(role: .user, text: "質問"), answer, resident, unfinishedResident], workspaceID: nil)
    let data = try JSONEncoder().encode(snapshot)
    let restored = try AIConversationSnapshot.decode(data, workspaceID: nil).restoredMessages()
    precondition(restored.count == 3 && restored[1].id == answer.id)
    precondition(restored[1].sources == answer.sources && restored[1].details == answer.details)
    precondition(restored[1].interfaceTaskIDs.isEmpty && restored[1].interfaceProjectIDs.isEmpty)
    precondition(restored[1].calendarReadSnapshot == nil)
    precondition(restored[1].mcpResultAuthorizationIDs.isEmpty)
    precondition(!String(decoding: data, as: UTF8.self).contains(externalGrant.uuidString))
    precondition(!String(decoding: data, as: UTF8.self).contains("never-persist-eventkit-id"))
    precondition(restored[1].cloudAuthorizationTargets == nil && restored[1].interfaceWorkspaceID == nil)
    precondition(restored[1].artifactProvenance == answer.artifactProvenance)
    var legacyJSON = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var oldTurns = legacyJSON["turns"] as! [[String: Any]]
    for index in oldTurns.indices { oldTurns[index].removeValue(forKey: "artifactProvenance") }
    legacyJSON["turns"] = oldTurns
    let old = try AIConversationSnapshot.decode(JSONSerialization.data(withJSONObject: legacyJSON), workspaceID: nil)
    precondition(old.restoredMessages()[1].artifactProvenance == nil)
    precondition(restored[2].residentName == "朝" && restored[2].suggestions == resident.suggestions)
    precondition(!restored.contains(where: \.isThinking))
    var interrupted = answer
    interrupted.isThinking = true
    interrupted.text = "途中\n```memora-ui\n{}"
    let recovered = AIConversationSnapshot(messages: [interrupted], workspaceID: nil).restoredMessages()[0]
    precondition(recovered.didChangeData && recovered.cloudProvenance == nil && !recovered.isThinking)
    precondition(recovered.text.contains("自動再実行しません") && !recovered.text.contains("memora-ui"))
    let blank = AIConversationSnapshot(messages: [], workspaceID: nil)
    let decodedBlank = try AIConversationSnapshot.decode(JSONEncoder().encode(blank), workspaceID: nil)
    precondition(decodedBlank.turns.isEmpty)
    try reject(data, workspaceID: "other")
    var invalid = snapshot
    invalid.version = 9
    try reject(JSONEncoder().encode(invalid))
    invalid = snapshot
    invalid.turns.append(invalid.turns[0])
    try reject(JSONEncoder().encode(invalid))
    invalid = snapshot
    invalid.turns[0].role = "system"
    try reject(JSONEncoder().encode(invalid))
    invalid = snapshot
    invalid.turns[1].artifactProvenance?.workspaceID = "other"
    try reject(JSONEncoder().encode(invalid))
    invalid = snapshot
    invalid.turns[1].artifactProvenance?.records.append(answer.artifactProvenance!.records[0])
    try reject(JSONEncoder().encode(invalid))
    invalid = snapshot
    invalid.turns[0].text = String(repeating: "\\", count: AIConversationSnapshot.maximumBytes / 6)
    try reject(JSONEncoder().encode(invalid))
    try reject(Data(repeating: 32, count: AIConversationSnapshot.maximumBytes + 1))
    print("AI conversation snapshot checks passed")
  }

  static func reject(_ data: Data, workspaceID: String? = nil) throws {
    do {
      _ = try AIConversationSnapshot.decode(data, workspaceID: workspaceID)
      preconditionFailure("invalid snapshot accepted")
    } catch {}
  }
}
