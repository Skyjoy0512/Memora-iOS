import Foundation

extension MemoraModel {
  func readPersonTool(_ call: AgentToolCall, messageID: UUID, compact: Bool, purpose: RecordAccessPolicy.Purpose? = nil) -> AgentToolOutcome {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected else { return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true) }
    let name = call.string("name")
    let explicitID = call.string("person_id")
    if let policy = agentPluginPolicies[messageID], let personID = policy.personID {
      guard UUID(uuidString: explicitID) == personID, personPolicyIsCurrent(policy) else {
        return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
      }
    }
    let candidates: [Person]
    if !explicitID.isEmpty {
      guard let id = UUID(uuidString: explicitID), let person = person(id: id) else {
        return AgentToolOutcome(text: "人物IDが無効です。人物を選び直してください。", isError: true)
      }
      candidates = [person]
    } else { candidates = PersonIdentity.candidates(for: name, in: people) }
    if let purpose, !candidates.allSatisfy({ allowsPersonAccess($0.id, purpose: purpose) }) {
      return AgentToolOutcome(text: RecordAccessPolicy.personRefusal, isError: true)
    }
    guard !name.isEmpty || !explicitID.isEmpty, candidates.count == 1, let person = candidates.first,
          var memory = memory(of: person.id) else {
      recordArtifactReads(candidates.prefix(30).map { .person($0.id) }, messageID: messageID)
      if purpose != nil, purpose != .onDeviceAI { recordCloudReads(candidates.prefix(30).map { .person($0.id) }, messageID: messageID) }
      if purpose == .onDeviceAI { markCloudProvenanceIncomplete(messageID) }
      return AgentToolOutcome(text: candidates.isEmpty ? "該当する人物はいません。" :
        "人物候補です。複数なら本人に確認し、person_idで指定してください。\n" + candidates.prefix(30).map { "id=\($0.id) \($0.name)" }.joined(separator: "\n"))
    }
    if let policy = agentPluginPolicies[messageID], policy.personID != nil {
      memory.meetings = memory.meetings.filter { policy.recordIDs.contains($0.id) }
      memory.assignedTasks = memory.assignedTasks.filter { policy.includesTask(id: $0.id, meetingID: $0.meetingID) }
      memory.nameMatchedTasks = memory.nameMatchedTasks.filter { policy.includesTask(id: $0.id, meetingID: $0.meetingID) }
      memory.sharedTasks = memory.sharedTasks.filter { policy.includesTask(id: $0.id, meetingID: $0.meetingID) }
      memory.journalEntries = memory.journalEntries.filter { policy.personJournalIDs.contains($0.id) }
      memory.nameMatchedJournalEntries = []
      memory.decisions = memory.decisions.filter { policy.recordIDs.contains($0.meetingID) }
    }
    if let purpose {
      memory.meetings = memory.meetings.filter { allowsRecordAccess($0.id, purpose: purpose) }
      memory.assignedTasks = memory.assignedTasks.filter { allowsTaskAccess($0, purpose: purpose) }
      memory.nameMatchedTasks = memory.nameMatchedTasks.filter { allowsTaskAccess($0, purpose: purpose) }
      memory.sharedTasks = memory.sharedTasks.filter { allowsTaskAccess($0, purpose: purpose) }
      memory.journalEntries = memory.journalEntries.filter { allowsJournalAccess($0, purpose: purpose) }
      memory.nameMatchedJournalEntries = memory.nameMatchedJournalEntries.filter { allowsJournalAccess($0, purpose: purpose) }
      let ids = Set(memory.meetings.map(\.id))
      memory.decisions = memory.decisions.filter { ids.contains($0.meetingID) }
      if purpose != .onDeviceAI {
        recordCloudReads([.person(person.id)] + memory.meetings.map { .meeting($0.id) }
          + (memory.assignedTasks + memory.sharedTasks + memory.nameMatchedTasks).map { .task($0.id) }
          + (memory.journalEntries + memory.nameMatchedJournalEntries).map { .journal($0.id) }, messageID: messageID)
      }
    }
    recordArtifactReads([.person(person.id)] + memory.meetings.map { .meeting($0.id) }
      + (memory.assignedTasks + memory.sharedTasks + memory.nameMatchedTasks).map { .task($0.id) }
      + (memory.journalEntries + memory.nameMatchedJournalEntries).map { .journal($0.id) }, messageID: messageID)
    if purpose == .onDeviceAI || (purpose == nil && !compact) { markCloudProvenanceIncomplete(messageID) }
    let stepID = beginAgentStep(AgentStep(icon: AgentTool.readPerson.icon, title: "\(person.name)さんの記録を確認"), on: messageID)
    finishAgentStep(stepID, on: messageID, state: .done, detail: "会議\(memory.meetings.count)件")

    let meetingLimit = compact ? 4 : 12
    let taskLimit = compact ? 5 : 20
    let context = PersonAIContext(person)
    var parts = ["\(context.name)さん"]
    if let note = context.note, !note.isEmpty { parts.append("メモ: \(note)") }
    if let lastMet = memory.lastMet {
      parts.append("最後に会った日: \(Self.agentDate(lastMet))、一緒の会議: \(memory.meetings.count)件")
    }
    if !memory.assignedTasks.isEmpty {
      parts.append("## 人物IDで指定された担当タスク（発言・約束の確定ではない）\n" + memory.assignedTasks.prefix(taskLimit).map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !memory.nameMatchedTasks.isEmpty {
      parts.append("## 担当名のみ一致するタスク（本人未確認）\n" + memory.nameMatchedTasks.prefix(taskLimit).map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !memory.sharedTasks.isEmpty {
      parts.append("## 一緒の会議で残っていること\n" + memory.sharedTasks.prefix(taskLimit).map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !memory.decisions.isEmpty {
      parts.append("## 関連する会議の決定（本人の発言・合意とは断定しない）\n" + memory.decisions.prefix(taskLimit).map {
        "- \($0.text)（\($0.meetingTitle)、\(Self.agentDate($0.date))）"
      }.joined(separator: "\n"))
    }
    if !memory.meetings.isEmpty {
      parts.append("## 一緒の会議（新しい順）\n" + memory.meetings.prefix(meetingLimit).map { meeting in
        let preview = meeting.summaryPreview.replacingOccurrences(of: "\n", with: " ").prefix(compact ? 60 : 160)
        return "- id=\(meeting.id.uuidString) 「\(meeting.displayTitle)」 \(Self.agentDate(meeting.createdAt)) \(preview)"
      }.joined(separator: "\n"))
    }
    let journalEntries = memory.journalEntries.filter {
      AIJournalPrivacy.allowsReading(kind: $0.kind, origin: $0.origin)
    }
    if !journalEntries.isEmpty {
      parts.append("## 人物IDで関連付けたジャーナル（本人の発言・参加の確定ではない）\n" + journalEntries.prefix(compact ? 3 : 8).map {
        "- id=\($0.id) \($0.title)（\(Self.agentDate($0.occurredAt))） \(String($0.summary.prefix(compact ? 100 : 500)))"
      }.joined(separator: "\n"))
    }
    let mentions = memory.nameMatchedJournalEntries.filter { AIJournalPrivacy.allowsReading(kind: $0.kind, origin: $0.origin) }
    if !mentions.isEmpty {
      parts.append("## 名前の言及のみ・本人未確認のジャーナル\n" + mentions.prefix(compact ? 2 : 4).map {
        "- id=\($0.id) \($0.title)（\(Self.agentDate($0.occurredAt))）"
      }.joined(separator: "\n"))
    }
    return AgentToolOutcome(text: parts.joined(separator: "\n\n"))
  }

}
