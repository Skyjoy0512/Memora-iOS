import Foundation

extension MemoraModel {
  func invalidateAICalendarContext() {
    calendarContextRevision = UUID()
    if isAIChatResponding, aiMessages.contains(where: { $0.isThinking && $0.calendarReadSnapshot != nil }) {
      stopAIChat()
    }
  }

  func readCalendarTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    guard CalendarService.access == .granted else {
      return AgentToolOutcome(text: "端末のカレンダーを読み取る権限がありません。ジャーナルのカレンダー設定でアクセスを許可してください。Google Calendarの直接連携ではありません。", isError: true)
    }
    guard let context = CalendarAgentReadContext(in: self, call: call, messageID: messageID),
          let message = agentMessage(messageID) else {
      return AgentToolOutcome(text: "予定の参照範囲または実行権限を確認できません。取得していません。", isError: true)
    }
    let workspaceID = currentTeamID
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let text = call.arguments["date"] as? String, text.count == 10,
          let date = formatter.date(from: text), formatter.string(from: date) == text else {
      return AgentToolOutcome(text: "日付は yyyy-MM-dd で指定してください。", isError: true)
    }
    // Observe changes during approval as well, without fetching event contents.
    CalendarService.beginAIObservation()
    let step = beginAgentStep(AgentStep(icon: .calendar, title: "カレンダーを確認"), on: messageID)
    if message.cloudProvenance != nil {
      let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .calendar,
        title: "予定を選択中のAIへ共有", lines: ["対象日: " + text, "共有する内容: 予定名・開始/終了日時・終日設定（最大30件）。"], confirmTitle: "共有する"), changesData: false)
      guard context.isCurrent(in: self) else {
        failCalendarRead(call, messageID: messageID, stepID: step, context: context)
        return AgentToolOutcome(text: AIAnswerFailure.contextChanged.message, isError: true)
      }
      guard approved, !Task.isCancelled else {
        agentBlockedExternalTools[messageID, default: []].insert(call.name)
        finishAgentStep(step, on: messageID, state: .declined)
        return AgentToolOutcome(text: "予定の共有は承認されなかったため、取得していません。")
      }
    }
    guard context.isCurrent(in: self) else {
      failCalendarRead(call, messageID: messageID, stepID: step, context: context)
      return AgentToolOutcome(text: "予定の参照権限が変わったため取得していません。", isError: true)
    }
    let events = await CalendarService.events(on: date)
    guard context.isCurrent(in: self) else {
      failCalendarRead(call, messageID: messageID, stepID: step, context: context)
      return AgentToolOutcome(text: "カレンダーの取得を停止しました。", isError: true)
    }
    finishAgentStep(step, on: messageID, state: .done, detail: "\(events.count)件")
    #if DEBUG
    // An actual completed read can be verified without logging dates or event contents.
    print("MemoraPlugin: read_calendar completed")
    #endif
    let incoming = events.prefix(30).map { event in
      AICalendarEventReference(sourceID: event.id, title: String(event.title.prefix(200)), start: event.start, end: event.end, isAllDay: event.isAllDay)
    }
    let previous = agentMessage(messageID)?.calendarReadSnapshot ?? AICalendarReadSnapshot(revision: context.revision, readAt: .now, events: [])
    let snapshot = previous.merging(incoming, at: .now)
    updateAgentMessage(messageID) { $0.calendarReadSnapshot = snapshot; $0.interfaceWorkspaceID = workspaceID }
    markCloudProvenanceIncomplete(messageID)
    let keys = Set(incoming.filter(\.isValid).map(\.sourceID))
    let rows: [[String: Any]] = snapshot.events.filter { keys.contains($0.sourceID) }.map { event in
      ["referenceID": event.id.uuidString, "title": event.title, "start": event.start.ISO8601Format(), "end": event.end.ISO8601Format(), "isAllDay": event.isAllDay]
    }
    let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])) ?? Data()
    let note = events.isEmpty ? "予定はありません。" : "参照可能な予定を表示（1日最大30件・1回答最大120件）。"
    return AgentToolOutcome(text: "端末のカレンダー・\(text)・取得\(events.count)件・参照可能\(rows.count)件。\(note)\n" + String(decoding: data, as: UTF8.self))
  }

  private func failCalendarRead(_ call: AgentToolCall, messageID: UUID, stepID: UUID, context: CalendarAgentReadContext) {
    // A late read must not finish a new/settled reply or change its tool denials.
    guard context.ownsMessage(in: self) else { return }
    agentBlockedExternalTools[messageID, default: []].insert(call.name)
    finishAgentStep(stepID, on: messageID, state: .failed, detail: "取得を停止")
  }
}
