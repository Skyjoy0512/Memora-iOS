import Foundation

extension MemoraModel {
  func reviewPeriodTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) -> AgentToolOutcome {
    guard let period = ReviewPeriod.parse(start: call.string("start_date"), end: call.string("end_date")) else {
      return AgentToolOutcome(text: "開始日と終了日をyyyy-MM-ddで指定してください。開始日から終了日まで最大366日です。", isError: true)
    }
    let allowed = Self.meetings(in: scope, from: meetings)
    let scopedTasks = scope == .all ? tasks : Self.tasks(in: allowed, from: tasks)
    let entries = scope == .all ? lifeLogEntries.filter { $0.kind != .location } : []
    let stepID = beginAgentStep(AgentStep(icon: .calendar, title: "期間の記録を集計しています"), on: messageID)
    let statistics = ReviewStatistics.build(period: period, meetings: allowed, tasks: scopedTasks, entries: entries)
    finishAgentStep(stepID, on: messageID, state: .done, detail: period.label)
    return AgentToolOutcome(text: "対象: \(scope.title)\n" + statistics.markdown(includesLocation: false))
  }
}
