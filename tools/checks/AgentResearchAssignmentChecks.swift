import Foundation

@main
struct AgentResearchAssignmentChecks {
  static func main() {
    let valid: [[String: Any]] = [
      ["role": " 会議整理 ", "request": "会議の決定を確認"],
      ["role": "タスク確認", "request": "未完了の担当と期限を確認"]
    ]
    precondition(AgentResearchAssignment.parse(valid)?.count == 2)
    precondition(AgentResearchAssignment.parse(valid)?.first?.role == "会議整理")
    precondition(AgentResearchAssignment.parse([]) == nil)
    precondition(AgentResearchAssignment.parse([valid[0]]) == nil)
    precondition(AgentResearchAssignment.parse(valid + valid) == nil)
    precondition(AgentResearchAssignment.parse([valid[0], valid[0]]) == nil)
    precondition(AgentResearchAssignment.parse([valid[0], ["role": "", "request": "確認"]]) == nil)
    precondition(AgentResearchAssignment.parse([valid[0], ["role": 2, "request": "確認"]]) == nil)
    precondition(AgentResearchAssignment.parse([valid[0], ["role": "別担当", "request": String(repeating: "文", count: 2_001)]]) == nil)
    print("AgentResearchAssignment checks passed")
  }
}
