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
    print("ResidentLimitsChecks: passed (legacy decode, policy persistence, bounded requests/tools, whitelist cannot grant writes, notification setting)")
  }
}
