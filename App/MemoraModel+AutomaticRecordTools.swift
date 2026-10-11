import Foundation

extension MemoraModel {
  func automaticRecordTool(_ call: AgentToolCall, messageID: UUID) -> AgentToolOutcome? {
    guard let tool = call.tool else { return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true) }
    guard [.searchRecords, .readRecord, .listProjects, .listTasks, .readPerson, .reviewPeriod].contains(tool) else {
      return nil
    }
    guard !isRestoring, !isStoreProtected else {
      return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
    }
    let permitted = meetings.filter { RecordAccessPolicy.allows($0.effectivePrivacy, purpose: .automaticAgent) }
    let ids = Set(permitted.map(\.id))
    let permittedTasks = tasks.filter { $0.meetingID.map(ids.contains) == true }
    var lines: [String] = []
    switch tool {
    case .searchRecords:
      let terms = Self.questionWords(in: call.string("query"))
      let limit = min(max(call.int("limit") ?? 8, 1), 20)
      let found = permitted.filter { record in
        terms.isEmpty || terms.contains { searchText(for: record).localizedCaseInsensitiveContains($0) }
      }.sorted { $0.createdAt > $1.createdAt }.prefix(limit)
      lines = found.map { "id=\($0.id) 「\($0.displayTitle)」 \($0.shortSummaryPreview)" }
    case .readRecord:
      guard let id = UUID(uuidString: call.string("id")), let record = permitted.first(where: { $0.id == id }) else {
        return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
      }
      lines = ["id=\(record.id) 「\(record.displayTitle)」", record.summary,
        record.keyPoints.joined(separator: "\n"), record.decisions.joined(separator: "\n"),
        record.openQuestions.joined(separator: "\n"), record.notes,
        String(record.transcript.map(MeetingSummaryInput.line(for:)).joined(separator: "\n").prefix(24_000))]
      updateAgentMessage(messageID) { message in
        if !message.sources.contains(where: { $0.meetingID == id }) {
          message.sources.append(AIChatSource(meetingID: id, title: record.displayTitle))
        }
      }
    case .listProjects:
      let projects = Set(permitted.compactMap(\.spaceID))
      lines = spaces.filter { projects.contains($0.id) }.map { "id=\($0.id) 「\($0.name)」" }
    case .listTasks:
      lines = permittedTasks.filter { call.bool("include_completed") || !$0.isCompleted }.prefix(80)
        .map { "id=\($0.id) \($0.title) \($0.detail)" }
    case .readPerson:
      let name = call.string("name")
      let peopleIDs = Set(permitted.compactMap(\.participantIDs).flatMap { $0 })
      let visiblePeople = people.filter { peopleIDs.contains($0.id) }
      if name.isEmpty { lines = visiblePeople.map(\.name) }
      else if let person = visiblePeople.first(where: { $0.name.localizedStandardContains(name) }) {
        lines = permitted.filter { $0.participantIDs?.contains(person.id) == true }
          .map { "id=\($0.id) 「\($0.displayTitle)」 \($0.shortSummaryPreview)" }
      }
    case .reviewPeriod:
      let start = Self.automaticReviewDate(call.string("start_date"))
      let end = Self.automaticReviewDate(call.string("end_date")).flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }
      guard let start, let end, start < end else {
        return AgentToolOutcome(text: "start_date/end_dateをYYYY-MM-DDで指定してください。", isError: true)
      }
      lines = permitted.filter { $0.createdAt >= start && $0.createdAt < end }.map {
        "「\($0.displayTitle)」 \($0.summaryPreview)\n\($0.decisions.joined(separator: "\n"))"
      }
    default: break
    }
    let step = beginAgentStep(AgentStep(icon: tool.icon, title: "許可された記録を確認"), on: messageID)
    finishAgentStep(step, on: messageID, state: .done, detail: "外部送信許可を適用")
    return AgentToolOutcome(text: lines.isEmpty ? "外部送信が許可された該当記録はありません。未判定・未許可の記録は読みません。" : String(lines.joined(separator: "\n").prefix(32_000)))
  }

  private static func automaticReviewDate(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: text)
  }
}
