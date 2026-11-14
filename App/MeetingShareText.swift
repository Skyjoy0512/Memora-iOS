import Foundation

/// A plain-text summary of a meeting for the system share sheet — Messages,
/// Mail, Notion, or anything else the person has.
enum MeetingShareText {
  static func make(meeting: Meeting, tasks: [MemoraTask]) -> String {
    var lines: [String] = [
      meeting.displayTitle,
      "\(meeting.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP")))) · \(MemoraFormat.duration(meeting.duration))"
    ]

    if !meeting.summary.isEmpty {
      lines.append(contentsOf: ["", meeting.summary])
    }

    let decisions = SummaryContentProjection.supplements(meeting.decisions, markdown: meeting.summary)
    if !decisions.isEmpty {
      lines.append(contentsOf: ["", "決まったこと"])
      lines.append(contentsOf: decisions.map { "・\($0)" })
    }

    let meetingTasks = tasks.filter { $0.meetingID == meeting.id }
    if !meetingTasks.isEmpty {
      lines.append(contentsOf: ["", "タスク（現在の状態）"])
      lines.append(contentsOf: meetingTasks.map { task in
        let state = task.isCompleted ? "完了" : "未完了"
        guard let assignee = task.assignee, !assignee.isEmpty else { return "・[\(state)] \(task.title)" }
        return "・[\(state)] \(task.title)（\(assignee)）"
      })
    }

    let questions = SummaryContentProjection.supplements(meeting.openQuestions, markdown: meeting.summary)
    if !questions.isEmpty {
      lines.append(contentsOf: ["", "まだ決まっていないこと"])
      lines.append(contentsOf: questions.map { "・\($0)" })
    }

    // A `memora://` link only resolves on the device that holds the record, so
    // it is not added to shared text as if others could open it.

    lines.append(contentsOf: ["", "Memora で共有"])
    return lines.joined(separator: "\n")
  }
}
