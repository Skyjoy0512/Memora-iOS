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
    guard calendarCallIsCurrent(call, messageID: messageID), let message = agentMessage(messageID) else {
      return AgentToolOutcome(text: "予定の参照範囲または実行権限を確認できません。取得していません。", isError: true)
    }
    let workspaceID = currentTeamID
    let policy = agentPluginPolicies[messageID]
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
    let step = beginAgentStep(AgentStep(icon: .calendar, title: "カレンダーを確認"), on: messageID)
    if message.cloudProvenance != nil {
      let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .calendar,
        title: "予定を選択中のAIへ共有", lines: ["対象日: " + text, "共有する内容: 予定名・開始/終了日時・終日設定（最大30件）。"], confirmTitle: "共有する"), changesData: false)
      guard approved, !Task.isCancelled else {
        agentBlockedExternalTools[messageID, default: []].insert(call.name)
        finishAgentStep(step, on: messageID, state: .declined)
        return AgentToolOutcome(text: "予定の共有は承認されなかったため、取得していません。")
      }
    }
    guard currentTeamID == workspaceID, agentPluginPolicies[messageID] == policy,
          calendarCallIsCurrent(call, messageID: messageID) else {
      finishAgentStep(step, on: messageID, state: .failed, detail: "参照権限が変更されました")
      return AgentToolOutcome(text: "予定の参照権限が変わったため取得していません。", isError: true)
    }
    CalendarService.beginAIObservation()
    let revision = calendarContextRevision
    let events = await CalendarService.events(on: date)
    guard currentTeamID == workspaceID, agentPluginPolicies[messageID] == policy,
          calendarContextRevision == revision, calendarCallIsCurrent(call, messageID: messageID) else {
      finishAgentStep(step, on: messageID, state: .failed, detail: "取得を停止")
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
    let previous = agentMessage(messageID)?.calendarReadSnapshot ?? AICalendarReadSnapshot(revision: revision, readAt: .now, events: [])
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

  private func calendarCallIsCurrent(_ call: AgentToolCall, messageID: UUID) -> Bool {
    guard call.tool == .readCalendar, !Task.isCancelled, currentTeamID == nil, !isRestoring, !isStoreProtected,
          !agentBlockedExternalTools[messageID, default: []].contains(call.name),
          integrationIsEnabled("calendar"), CalendarService.access == .granted, let message = agentMessage(messageID),
          calendarReadIsCurrent(message.calendarReadSnapshot), pluginCallIsPermitted(call, messageID: messageID),
          toolRegistry().permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID]) else { return false }
    if let policy = agentPluginPolicies[messageID], !personPolicyIsCurrent(policy) { return false }
    return message.cloudProvenance == nil || isCloudSessionAuthorized(messageID)
  }
}
