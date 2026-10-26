import Foundation

@main
struct ResidentLimitsChecks {
  static func main() throws {
    var limits = ResidentExecutionLimits()
    precondition(limits.modelTurnLimit == 8 && limits.toolCallLimit == 12)
    let readTools: Set<String> = ["search_records", "read_record", "list_tasks"]
    precondition(limits.permits("list_tasks", availableReadTools: readTools))
    limits.allowedToolNames = ["list_tasks", "create_document"]
    precondition(limits.permits("list_tasks", availableReadTools: readTools))
    precondition(!limits.permits("read_record", availableReadTools: readTools))
    precondition(!limits.permits("create_document", availableReadTools: readTools))
    limits.maximumModelTurns = 1_000; limits.maximumToolCalls = 1_000
    precondition(limits.modelTurnLimit == 8 && limits.toolCallLimit == 24)
    limits.maximumModelTurns = -1; limits.maximumToolCalls = -1
    precondition(limits.modelTurnLimit == 1 && limits.toolCallLimit == 0)
    var agent = ResidentAgent(id: UUID(), name: "test", role: "read", instructions: "read only", symbol: .calendar, trigger: .dailyMorning)
    let oldData = try JSONEncoder().encode(agent)
    let oldAgent = try JSONDecoder().decode(ResidentAgent.self, from: oldData)
    precondition(oldAgent.executionLimits == nil)
    limits.notifies = false
    agent.executionLimits = limits
    let decoded = try JSONDecoder().decode(ResidentAgent.self, from: JSONEncoder().encode(agent))
    precondition(decoded.executionLimits == limits)
    checkSchedule()
    print("ResidentLimitsChecks: passed (legacy decode, bounded requests/tools, read whitelist, notification setting, daily/weekly expiry, duplicate suppression, DST and event-trigger separation; no OS scheduling guarantee)")
  }

  static func checkSchedule() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    let daily = ResidentTrigger.dailyMorning
    precondition(!daily.shouldRun(at: date(26, 7, 59), lastRunAt: nil, calendar: calendar))
    precondition(daily.shouldRun(at: date(26, 8), lastRunAt: nil, calendar: calendar))
    precondition(daily.shouldRun(at: date(26, 17, 59), lastRunAt: date(25, 8), calendar: calendar))
    precondition(!daily.shouldRun(at: date(26, 18), lastRunAt: nil, calendar: calendar))
    precondition(!daily.shouldRun(at: date(26, 8), lastRunAt: date(26, 8), calendar: calendar))
    precondition(!daily.shouldRun(at: date(26, 9), lastRunAt: date(27, 8), calendar: calendar))
    precondition(daily.nextDue(after: date(26, 8), calendar: calendar) == date(27, 8))

    let weekly = ResidentTrigger.weeklyMonday
    precondition(!weekly.shouldRun(at: date(26, 8, 59), lastRunAt: nil, calendar: calendar))
    precondition(weekly.shouldRun(at: date(26, 9), lastRunAt: nil, calendar: calendar))
    precondition(weekly.shouldRun(at: date(29, 8, 59), lastRunAt: nil, calendar: calendar))
    precondition(!weekly.shouldRun(at: date(29, 9), lastRunAt: nil, calendar: calendar))
    precondition(!weekly.shouldRun(at: date(27, 9), lastRunAt: date(26, 9), calendar: calendar))
    precondition(!ResidentTrigger.afterMeeting.shouldRun(at: date(26, 9), lastRunAt: nil, calendar: calendar))
    precondition(ResidentTrigger.afterMeeting.nextDue(after: date(26, 9), calendar: calendar) == nil)

    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    for (month, day) in [(3, 8), (11, 1)] {
      let due = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 8))!
      precondition(daily.shouldRun(at: due, lastRunAt: nil, calendar: calendar))
      precondition(!daily.shouldRun(at: due.addingTimeInterval(10 * 3_600), lastRunAt: nil, calendar: calendar))
      let next = daily.nextDue(after: due, calendar: calendar)!
      precondition(calendar.component(.hour, from: next) == 8)
      precondition(calendar.component(.day, from: next) == day + 1)
    }
  }
}
