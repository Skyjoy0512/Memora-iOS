import Foundation

extension MemoraModel {
  func automaticRecordTool(_ call: AgentToolCall, messageID: UUID,
                           purpose: RecordAccessPolicy.Purpose = .automaticAgent,
                           scope: AIChatScope = .all) -> AgentToolOutcome? {
    guard let tool = call.tool else {
      return purpose == .automaticAgent ? AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true) : nil
    }
    guard [.searchRecords, .readRecord, .listProjects, .listTasks, .readPerson, .reviewPeriod].contains(tool) else {
      return nil
    }
    guard currentTeamID == nil, !isRestoring, !isStoreProtected else {
      return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
    }
    let personPolicy = agentPluginPolicies[messageID].flatMap { $0.personID == nil ? nil : $0 }
    if let personPolicy, !personPolicyIsCurrent(personPolicy) {
      return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
    }
    let permitted = Self.meetings(in: scope, from: meetings)
      .filter { RecordAccessPolicy.allows($0.effectivePrivacy, purpose: purpose)
        && (personPolicy == nil || personPolicy?.recordIDs.contains($0.id) == true) }
    let permittedTasks = self.permittedTasks(for: purpose, scope: scope).filter { task in
      personPolicy?.includesTask(id: task.id, meetingID: task.meetingID) ?? true
    }
    let entries = scope == .all ? lifeLogEntries.filter {
      allowsJournalAccess($0, purpose: purpose) && (personPolicy == nil || personPolicy?.personJournalIDs.contains($0.id) == true)
    } : []
    var lines: [String] = []
    var references: [RecordPrivacyTarget] = []
    switch tool {
    case .searchRecords:
      let terms = Self.questionWords(in: call.string("query"))
      let limit = min(max(call.int("limit") ?? 8, 1), 20)
      let found = permitted.filter { record in
        terms.isEmpty || terms.contains { searchText(for: record).localizedCaseInsensitiveContains($0) }
      }
      let journal = entries.filter { entry in
        terms.isEmpty || terms.contains { (entry.title + " " + entry.summary).localizedCaseInsensitiveContains($0) }
      }
      let results = found.map { ($0.createdAt, "id=\($0.id) 録音「\($0.displayTitle)」 \($0.shortSummaryPreview)", RecordPrivacyTarget.meeting($0.id)) }
        + journal.map { ($0.occurredAt, "id=\($0.id) ジャーナル「\($0.title)」 \(String($0.summary.prefix(300)))", RecordPrivacyTarget.journal($0.id)) }
      let selected = results.sorted { $0.0 > $1.0 }.prefix(limit)
      lines = selected.map { $0.1 }
      references = selected.map { $0.2 }
      if purpose == .cloudAI { lines += agentSourceMatches(query: call.string("query"), messageID: messageID) }
    case .readRecord:
      guard let id = UUID(uuidString: call.string("id")) else {
        return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
      }
      if let entry = entries.first(where: { $0.id == id }) {
        references = [.journal(entry.id)]
        lines = ["id=\(entry.id) ジャーナル「\(entry.title)」", "日時: \(entry.occurredAt.formatted())",
          String(entry.summary.prefix(24_000))]
        break
      }
      guard let record = permitted.first(where: { $0.id == id }) else {
        return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
      }
      lines = ["id=\(record.id) 「\(record.displayTitle)」", record.summary,
        record.keyPoints.joined(separator: "\n"), record.decisions.joined(separator: "\n"),
        record.openQuestions.joined(separator: "\n"), record.notes,
        String(record.transcript.map(MeetingSummaryInput.line(for:)).joined(separator: "\n").prefix(24_000))]
      references = [.meeting(record.id)]
      updateAgentMessage(messageID) { message in
        if !message.sources.contains(where: { $0.meetingID == id }) {
          message.sources.append(AIChatSource(meetingID: id, title: record.displayTitle))
        }
      }
    case .listProjects:
      markCloudProvenanceIncomplete(messageID)
      let projects = Set(permitted.compactMap(\.spaceID))
      updateAgentMessage(messageID) { $0.interfaceProjectIDs.formUnion(projects); $0.interfaceWorkspaceID = currentTeamID }
      lines = spaces.filter { projects.contains($0.id) }.map { "id=\($0.id) 「\($0.name)」" }
    case .listTasks:
      let visibleIDs = permittedTasks.filter { call.bool("include_completed") || !$0.isCompleted }.prefix(80).map(\.id)
      updateAgentMessage(messageID) { $0.interfaceTaskIDs.formUnion(visibleIDs); $0.interfaceWorkspaceID = currentTeamID }
      references = permittedTasks.filter { call.bool("include_completed") || !$0.isCompleted }.prefix(80).map { .task($0.id) }
      lines = permittedTasks.filter { call.bool("include_completed") || !$0.isCompleted }.prefix(80)
        .map { "id=\($0.id) \($0.title) \($0.detail) / 担当: \($0.assignee ?? "未定") / 期限: \($0.dueDate?.formatted(date: .numeric, time: .omitted) ?? "未定") / \($0.statusLabel)" }
    case .readPerson:
      return readPersonTool(call, messageID: messageID, compact: false, purpose: purpose)
    case .reviewPeriod:
      guard let period = ReviewPeriod.parse(start: call.string("start_date"), end: call.string("end_date")) else {
        return AgentToolOutcome(text: "start_date/end_dateをYYYY-MM-DDで指定してください。期間は最大366日です。", isError: true)
      }
      let records = permitted.filter { period.contains($0.createdAt) }
      let complete = permittedTasks.filter { $0.isCompleted && $0.completedAt.map(period.contains) == true }.count
      let journal = entries.filter { period.contains($0.occurredAt) }
      references = records.map { .meeting($0.id) } + journal.map { .journal($0.id) } + permittedTasks.map { .task($0.id) }
      lines = ["対象期間: \(period.label)", "外部利用を許可した記録: \(records.count)件",
        "録音時間: \(MemoraFormat.duration(records.reduce(0) { $0 + ($1.duration.isFinite ? max(0, $1.duration) : 0) }))",
        "期間内に完了した関連タスク: \(complete)件",
        "ジャーナル: \(journal.count)件（メモ: \(journal.filter { $0.kind == .memo }.count)件 / 写真: \(journal.filter { $0.kind == .photo }.count)件）",
        "外部利用が許可された範囲の集計です。未許可記録・位置情報は含みません。"] + records.map {
        "「\($0.displayTitle)」 \($0.summaryPreview)\n\($0.decisions.joined(separator: "\n"))"
      } + journal.map { "ジャーナル「\($0.title)」 \(String($0.summary.prefix(600)))" }
    default: break
    }
    recordCloudReads(references, messageID: messageID)
    let step = beginAgentStep(AgentStep(icon: tool.icon, title: "許可された記録を確認"), on: messageID)
    finishAgentStep(step, on: messageID, state: .done, detail: "外部送信許可を適用")
    return AgentToolOutcome(text: lines.isEmpty ? "外部送信が許可された該当記録はありません。未判定・未許可の記録は読みません。" : String(lines.joined(separator: "\n").prefix(32_000)))
  }

}
