import Foundation

@main
enum AIConversationSnapshotChecks {
  static func main() throws {
    var answer = AIChatMessage(role: .assistant, text: "資料の回答【資料1】")
    let recordID = UUID()
    answer.sources = [AIChatSource(meetingID: recordID, title: "資料", excerpts: [.init(text: "根拠", start: 12)])]
    answer.details = AIAnswerDetails(scopeLabel: "すべて", engineLabel: "端末内", sourceCount: 1, generatedAt: .now)
    answer.sourceCitations = [.init(target: .source(UUID()), title: "長いPDF", excerpt: "最後のページの根拠", page: 24)]
    let file = AIAttachment(id: UUID(), name: "会話のPDF", url: URL(fileURLWithPath: "/fixture/AIAttachments/source.pdf"))
    let fileReference = AIAttachmentFileReference(file)!
    answer.attachmentCitations = [AIAttachmentCitation(number: 1, file: fileReference, excerpt: "添付の後半ページ", page: 24)!]
    answer.interfaceTaskIDs = [UUID()]
    answer.interfaceProjectIDs = [UUID()]
    answer.interfaceWorkspaceID = "private-team"
    let externalGrant = UUID()
    answer.mcpResultAuthorizationIDs = [externalGrant]
    let gmailGrant = UUID()
    answer.gmailResultAuthorizationIDs = [gmailGrant]
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
    precondition(restored[1].sourceCitations == answer.sourceCitations)
    precondition(restored[1].attachmentCitations == answer.attachmentCitations)
    let exchange = AIConversationEntry(id: UUID(), question: "添付について", answer: answer.text, scopeLabel: "すべて",
      createdAt: .now, attachmentCitations: answer.attachmentCitations, attachment: fileReference)
    let savedExchange = try JSONEncoder().encode(exchange)
    let restoredExchange = try JSONDecoder().decode(AIConversationEntry.self, from: savedExchange)
    precondition(restoredExchange.attachmentCitations == answer.attachmentCitations)
    var oldExchange = try JSONSerialization.jsonObject(with: savedExchange) as! [String: Any]
    oldExchange.removeValue(forKey: "attachmentCitations")
    let legacyExchange = try JSONDecoder().decode(AIConversationEntry.self, from: JSONSerialization.data(withJSONObject: oldExchange))
    precondition(legacyExchange.attachmentCitations == nil && legacyExchange.answer == answer.text)
    precondition(restored[1].interfaceTaskIDs.isEmpty && restored[1].interfaceProjectIDs.isEmpty)
    precondition(restored[1].calendarReadSnapshot == nil)
    precondition(restored[1].mcpResultAuthorizationIDs.isEmpty)
    precondition(restored[1].gmailResultAuthorizationIDs.isEmpty)
    precondition(!String(decoding: data, as: UTF8.self).contains(gmailGrant.uuidString))
    precondition(!String(decoding: data, as: UTF8.self).contains(externalGrant.uuidString))
    precondition(!String(decoding: data, as: UTF8.self).contains("never-persist-eventkit-id"))
    precondition(restored[1].cloudAuthorizationTargets == nil && restored[1].interfaceWorkspaceID == nil)
    precondition(restored[1].artifactProvenance == answer.artifactProvenance)
    var legacyJSON = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var oldTurns = legacyJSON["turns"] as! [[String: Any]]
    for index in oldTurns.indices {
      oldTurns[index].removeValue(forKey: "artifactProvenance")
      oldTurns[index].removeValue(forKey: "sourceCitations")
      oldTurns[index].removeValue(forKey: "attachmentCitations")
    }
    legacyJSON["turns"] = oldTurns
    let old = try AIConversationSnapshot.decode(JSONSerialization.data(withJSONObject: legacyJSON), workspaceID: nil)
    precondition(old.restoredMessages()[1].artifactProvenance == nil)
    precondition(old.restoredMessages()[1].sourceCitations.isEmpty)
    precondition(old.restoredMessages()[1].attachmentCitations.isEmpty)
    let attachmentRoot = URL(fileURLWithPath: "/fixture/AIAttachments")
    let secondFile = AIAttachment(id: UUID(), name: "字幕", url: attachmentRoot.appendingPathComponent("captions.vtt"))
    var multi = AIAttachment(id: UUID(), name: "PDF", url: attachmentRoot.appendingPathComponent("document.pdf"),
      originalURL: URL(string: "https://example.com/doc.pdf"))
    multi.append(secondFile)
    let reference = AIAttachmentFileReference(multi)!
    precondition(reference.isValid && reference.additionalFiles?.count == 1)
    let roundTrip = try JSONDecoder().decode(AIAttachmentFileReference.self, from: JSONEncoder().encode(reference))
    precondition(roundTrip == reference)
    var invalidReference = reference
    invalidReference.additionalFiles?[0].fileName = "../private.pdf"
    precondition(!invalidReference.isValid)
    precondition(restored[2].residentName == "朝" && restored[2].suggestions == resident.suggestions)
    precondition(!restored.contains(where: \.isThinking))
    var interrupted = answer
    interrupted.isThinking = true
    interrupted.text = "途中\n```memora-ui\n{}"
    let recovered = AIConversationSnapshot(messages: [interrupted], workspaceID: nil).restoredMessages()[0]
    precondition(!recovered.didChangeData && recovered.hasUnconfirmedDataChange && recovered.cloudProvenance == nil && !recovered.isThinking)
    precondition(recovered.text.contains("自動再実行しません") && !recovered.text.contains("memora-ui"))
    var uncertain = answer
    uncertain.hasUnconfirmedDataChange = true
    let uncertainData = try JSONEncoder().encode(AIConversationSnapshot(messages: [uncertain], workspaceID: nil))
    let uncertainRestored = try AIConversationSnapshot.decode(uncertainData, workspaceID: nil).restoredMessages()[0]
    precondition(uncertainRestored.hasUnconfirmedDataChange && !uncertainRestored.didChangeData)
    var legacyUncertain = try JSONSerialization.jsonObject(with: uncertainData) as! [String: Any]
    var legacyTurns = legacyUncertain["turns"] as! [[String: Any]]
    legacyTurns[0].removeValue(forKey: "hasUnconfirmedDataChange")
    legacyUncertain["turns"] = legacyTurns
    let oldUncertain = try AIConversationSnapshot.decode(JSONSerialization.data(withJSONObject: legacyUncertain), workspaceID: nil)
    precondition(!oldUncertain.restoredMessages()[0].hasUnconfirmedDataChange)
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
    invalid.turns[1].attachmentCitations?[0].file.fileName = "../private.pdf"
    try reject(JSONEncoder().encode(invalid))
    invalid = snapshot
    invalid.turns[1].attachmentCitations = Array(repeating: answer.attachmentCitations[0], count: 65)
    try reject(JSONEncoder().encode(invalid))
    invalid = snapshot
    invalid.turns[1].attachmentCitations = Array(repeating: answer.attachmentCitations[0], count: 2)
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
