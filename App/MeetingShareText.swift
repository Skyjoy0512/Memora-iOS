import Foundation

/// A plain-text summary of a meeting for the system share sheet — Messages,
/// Mail, Notion, or anything else the person has.
enum MeetingShareText {
  static func make(meeting: Meeting, tasks: [MemoraTask]) -> String {
    var lines: [String] = [
      meeting.title,
      "\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(MemoraFormat.duration(meeting.duration))"
    ]

    if !meeting.summary.isEmpty {
      lines.append(contentsOf: ["", meeting.summary])
    }

    if !meeting.decisions.isEmpty {
      lines.append(contentsOf: ["", "決まったこと"])
      lines.append(contentsOf: meeting.decisions.map { "・\($0)" })
    }

    let meetingTasks = tasks.filter { $0.meetingID == meeting.id }
    if !meetingTasks.isEmpty {
      lines.append(contentsOf: ["", "次の行動"])
      lines.append(contentsOf: meetingTasks.map { task in
        guard let assignee = task.assignee, !assignee.isEmpty else { return "・\(task.title)" }
        return "・\(task.title)（\(assignee)）"
      })
    }

    if !meeting.openQuestions.isEmpty {
      lines.append(contentsOf: ["", "まだ決まっていないこと"])
      lines.append(contentsOf: meeting.openQuestions.map { "・\($0)" })
    }

    lines.append(contentsOf: ["", "Memora で共有"])
    return lines.joined(separator: "\n")
  }
}
