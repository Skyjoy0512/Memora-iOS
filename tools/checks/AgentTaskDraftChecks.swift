import Foundation

@main
enum AgentTaskDraftChecks {
  static func main() throws {
    let meetingID = UUID()
    let parsed = try AgentTaskDraft.parse([["title": " 見積書を作成 ", "detail": "決定事項", "assignee": "田中", "due_date": "2026-10-20", "meeting_id": meetingID.uuidString], ["title": "議事録"]])
    precondition(parsed.count == 2 && parsed[0].title == "見積書を作成" && parsed[0].detail == "決定事項")
    precondition(parsed[0].dueDate != nil && parsed[1].dueDate == nil && parsed[1].assignee.isEmpty)
    var edited = parsed
    edited[0].title = "修正したタイトル"
    edited[0].detail = "確認した詳細"
    edited[0].assignee = "自分"
    edited[1].isSelected = false
    let selected = AgentTaskDraft.validatedSelection(edited, originals: parsed, allowedMeetingIDs: [meetingID])
    precondition(selected?.count == 1 && selected?.first?.detail == "確認した詳細")
    precondition(AgentTaskDraft.validatedSelection(edited, originals: parsed, allowedMeetingIDs: []) == nil)
    edited[0].meetingID = UUID()
    precondition(AgentTaskDraft.validatedSelection(edited, originals: parsed, allowedMeetingIDs: [edited[0].meetingID!]) == nil)
    edited = parsed
    edited[0].id = UUID()
    precondition(AgentTaskDraft.validatedSelection(edited, originals: parsed, allowedMeetingIDs: [meetingID]) == nil)
    edited = parsed.map { var copy = $0; copy.isSelected = false; return copy }
    precondition(AgentTaskDraft.validatedSelection(edited, originals: parsed, allowedMeetingIDs: [meetingID]) == nil)
    precondition(AgentTaskDraft.validatedSelection([parsed[0], parsed[0]], originals: parsed, allowedMeetingIDs: [meetingID]) == nil)
    for invalid: [[String: Any]] in [[], [["title": ""]], [["title": "期限", "due_date": "2026-02-30"]], [["title": "資料", "meeting_id": "not-uuid"]], [["title": String(repeating: "あ", count: 501)]], [["title": "資料", "detail": String(repeating: "x", count: 4_001)]], Array(repeating: ["title": "件数超過"], count: 31)] {
      do { _ = try AgentTaskDraft.parse(invalid); preconditionFailure("invalid task proposal accepted") }
      catch {}
    }
    print("AgentTaskDraftChecks: passed (strict proposal parsing, editable fields, source/identity binding, selection, date/text/count bounds; no records)")
  }
}
