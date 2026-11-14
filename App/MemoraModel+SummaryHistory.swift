import Foundation

extension MemoraModel {
  @discardableResult
  func restoreSummary(_ versionID: UUID, meetingID: UUID) -> Bool {
    guard let record = meeting(id: meetingID), !processing.isActive(meetingID),
          let version = record.summaryVersions.first(where: { $0.id == versionID }) else { return false }
    guard updateMeeting(meetingID, change: { meeting in
      if !meeting.summary.isEmpty, !meeting.summaryVersions.contains(where: { $0.markdown == meeting.summary }) {
        meeting.summaryVersions.append(.snapshot(record: meeting, templateID: nil,
          preferences: summaryPreferences, modelInfo: "手動編集・旧形式"))
      }
      meeting.summary = version.markdown
      meeting.keyPoints = version.keyPoints
      meeting.decisions = version.decisions
      meeting.openQuestions = version.openQuestions
      meeting.activeSummaryVersionID = version.id
      meeting.status = .ready
    }) else { return false }
    announce("要約を復元しました。タスク・原音声・文字起こしは変更していません。")
    return true
  }
}
