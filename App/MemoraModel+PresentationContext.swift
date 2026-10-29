import Foundation

// Deep context for a presentation: gathers what the records already hold about
// the request, the people and the decisions behind it, and hands the model a
// structured, source-linked evidence pack instead of the newest few records.
extension MemoraModel {
  /// Builds the pack from the current workspace only. Every source carries the
  /// permission it was read under; a record that is not allowed for cloud use
  /// is never included in the text sent to a provider.
  func presentationEvidencePack(
    query: String,
    purpose: String,
    audience: String = "",
    decision: String = "",
    projectID: UUID? = nil,
    task: ContextTaskKind = .presentation,
    cloud: Bool = true
  ) -> PresentationEvidencePack {
    let purposeType: RecordAccessPolicy.Purpose = cloud ? .cloudAI : .onDeviceAI
    let projectName = projectID.flatMap { space(id: $0)?.name }
    let workspaceMeetings = meetings.filter { meeting in
      (projectID == nil || meeting.spaceID == projectID)
        && (!cloud || allowsRecordAccess(meeting.id, purpose: purposeType))
    }
    var sources: [PresentationEvidenceSource] = []
    for meeting in workspaceMeetings {
      var lines = [meeting.displayTitle]
      if !meeting.summary.isEmpty { lines.append(meeting.summary) }
      if !meeting.keyPoints.isEmpty { lines.append("要点: " + meeting.keyPoints.joined(separator: " / ")) }
      if !meeting.decisions.isEmpty { lines.append("決定: " + meeting.decisions.joined(separator: " / ")) }
      if !meeting.openQuestions.isEmpty { lines.append("未決: " + meeting.openQuestions.joined(separator: " / ")) }
      if !meeting.notes.isEmpty { lines.append(meeting.notes) }
      if let transcript = Self.presentationTranscriptExcerpt(meeting.transcript) { lines.append(transcript) }
      let permission: PresentationSourcePermission = meeting.effectivePrivacy.allowsCloudAI ? .allowed : .unknown
      sources.append(.init(id: "record:\(meeting.id.uuidString)", kind: .record,
        title: meeting.displayTitle, text: lines.joined(separator: "\n"),
        date: meeting.createdAt, updatedAt: meeting.createdAt,
        permission: cloud ? permission : .allowed, stance: .fact,
        confidence: meeting.status == .ready ? .confirmed : .reported,
        locator: meeting.summary.isEmpty ? "記録" : "要約"))
    }
    for task in tasks {
      guard !cloud || allowsTaskAccess(task, purpose: purposeType) else { continue }
      var lines = [task.title]
      if !task.detail.isEmpty { lines.append(task.detail) }
      if let assignee = task.assignee, !assignee.isEmpty { lines.append("担当: \(assignee)") }
      if let due = task.dueDate { lines.append("期限: \(due.formatted(date: .numeric, time: .omitted))") }
      sources.append(.init(id: "task:\(task.id.uuidString)", kind: .task, title: task.title,
        text: lines.joined(separator: "\n"), date: task.workDate ?? task.dueDate,
        updatedAt: task.completedAt, permission: .allowed, stance: .fact,
        confidence: task.isCompleted ? .confirmed : .reported))
    }
    for document in documents where projectID == nil || document.spaceID == projectID {
      let isFinalDeck = document.kind == .slides && document.artifactFileReference != nil
      let text = [document.title, document.markdown, document.plainText,
        document.slides.map(\.title).joined(separator: " / ")]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
      sources.append(.init(id: "document:\(document.id.uuidString)",
        kind: isFinalDeck ? .previousDeck : .document, title: document.title, text: text,
        date: document.createdAt, updatedAt: document.updatedAt, permission: .allowed,
        stance: .fact, confidence: isFinalDeck ? .confirmed : .reported,
        version: document.artifactRevision.map(String.init), isFinal: isFinalDeck))
    }
    for person in people {
      guard !cloud || allowsPersonAccess(person.id, purpose: purposeType) else { continue }
      let related = workspaceMeetings.filter { $0.participantIDs?.contains(person.id) == true }
      // Private notes stay on the device. Only the name, the meetings the person
      // was tagged on, and their own recorded lines are sent.
      var lines = [person.name]
      for meeting in related.prefix(8) {
        lines.append("会議: \(meeting.displayTitle) \(meeting.createdAt.formatted(date: .numeric, time: .omitted))")
        let quotes = meeting.transcript
          .filter { $0.speaker.contains(person.name) && !$0.text.isEmpty }
          .prefix(3)
          .map(\.text)
        if !quotes.isEmpty { lines.append("発言: " + quotes.joined(separator: " / ")) }
      }
      guard projectID == nil || !related.isEmpty else { continue }
      sources.append(.init(id: "person:\(person.id.uuidString)", kind: .person,
        title: person.name, text: lines.joined(separator: "\n"), permission: .allowed,
        stance: .fact, confidence: .reported))
    }
    if isAIMemoryEnabled {
      for memory in visibleAIMemories where memory.status == .current {
        sources.append(.init(id: "memory:\(memory.id.uuidString)", kind: .memory,
          title: "長期メモリ", text: memory.text, date: memory.updatedAt,
          updatedAt: memory.updatedAt, permission: .allowed, stance: .fact,
          confidence: .reported))
      }
    }
    for entry in lifeLogEntries.prefix(400) where projectID == nil {
      guard !cloud || RecordAccessPolicy.allows(entry.privacy, purpose: purposeType) else { continue }
      let text = [entry.title, entry.summary].filter { !$0.isEmpty }.joined(separator: "\n")
      sources.append(.init(id: "journal:\(entry.id.uuidString)", kind: .journal,
        title: entry.title, text: text, date: entry.occurredAt, updatedAt: entry.createdAt,
        permission: .allowed, stance: .fact, confidence: .reported))
    }
    let decisions = workspaceMeetings.flatMap { meeting -> [PresentationDecisionRecord] in
      meeting.decisions.enumerated().map { index, statement in
        let status = Self.presentationDecisionStatus(statement)
        return PresentationDecisionRecord(id: "decision:\(meeting.id.uuidString):\(index)",
          subject: Self.presentationDecisionSubject(statement, meeting: meeting),
          statement: statement, date: meeting.createdAt, status: status,
          decidedBy: nil, meetingTitle: meeting.displayTitle, supersedes: nil,
          rationale: nil, dissent: nil, unresolved: nil,
          sourceID: "record:\(meeting.id.uuidString)")
      }
    }
    // The pack is a prompt input, not a second copy of the archive: cap it.
    let budget = min(80_000, AIEngineService.contextCharacterLimit(for: askAIConfiguration.engine,
      llm: askAIConfiguration.llm, task: task) / 2)
    return PresentationContextBuilder.build(
      request: PresentationContextRequest(purpose: purpose, audience: audience,
        decisionRequired: decision, query: query, projectName: projectName),
      sources: sources, decisions: decisions, characterBudget: max(4_000, budget))
  }

  static func presentationDecisionStatus(_ statement: String) -> PresentationDecisionStatus {
    if statement.contains("撤回") || statement.contains("取り下げ") { return .withdrawn }
    if statement.contains("中止") || statement.contains("見送り") { return .cancelled }
    if statement.contains("未決") || statement.contains("保留") || statement.contains("継続検討") { return .open }
    if statement.contains("完了") { return .completed }
    if statement.contains("変更") || statement.contains("修正") { return .changed }
    if statement.contains("提案") || statement.contains("検討") { return .proposed }
    return .approved
  }

  static func presentationDecisionSubject(_ statement: String, meeting: Meeting) -> String {
    let stripped = ["撤回", "取り下げ", "中止", "見送り", "未決", "保留", "継続検討",
      "完了", "変更", "修正", "提案", "検討", "決定", "承認", "可決"].reduce(statement) {
      $0.replacingOccurrences(of: $1, with: "")
    }
    let subject = PresentationContextBuilder.normalize(stripped)
    return subject.isEmpty ? meeting.displayTitle : "\(meeting.displayTitle): \(String(subject.prefix(48)))"
  }

  private static func presentationTranscriptExcerpt(_ transcript: [TranscriptSegment]) -> String? {
    guard !transcript.isEmpty else { return nil }
    // The summary already carries the decisions; the transcript is only here
    // for a meeting that has no summary yet.
    let text = transcript.suffix(60).map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    return text.isEmpty ? nil : "文字起こし抜粋:\n" + String(text.prefix(4_000))
  }
}
