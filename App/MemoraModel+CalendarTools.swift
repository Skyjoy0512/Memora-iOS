import Foundation

extension MemoraModel {
  func readCalendarTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    guard CalendarService.access == .granted else {
      return AgentToolOutcome(text: "端末のカレンダーを読み取る権限がありません。ジャーナルのカレンダー設定でアクセスを許可してください。Google Calendarの直接連携ではありません。", isError: true)
    }
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
    let events = await CalendarService.events(on: date)
    guard !Task.isCancelled, integrationIsEnabled("calendar"), CalendarService.access == .granted else {
      finishAgentStep(step, on: messageID, state: .failed, detail: "取得を停止")
      return AgentToolOutcome(text: "カレンダーの取得を停止しました。", isError: true)
    }
    finishAgentStep(step, on: messageID, state: .done, detail: "\(events.count)件")
    let rows = events.prefix(30).map { event in
      let start = event.start.formatted(date: .omitted, time: .shortened)
      return "\(event.isAllDay ? "終日" : start) \(String(event.title.prefix(200)))"
    }
    return AgentToolOutcome(text: "端末のカレンダー・\(text)・\(events.count)件（最大30件を表示）\n" + (rows.isEmpty ? "予定はありません。" : rows.joined(separator: "\n")))
  }
}
