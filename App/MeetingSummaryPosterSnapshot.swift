import Foundation

struct MeetingSummaryPosterSnapshot: Identifiable {
  var id = UUID()
  var meetingID: UUID
  var workspaceGeneration: UUID
  var title: String
  var createdAt: Date
  var summary: String
  var privacy: RecordPrivacy

  @MainActor
  init?(meetingID: UUID, model: MemoraModel) {
    guard model.currentTeamID == nil, model.allowsRecordAccess(meetingID, purpose: .onDeviceAI),
          let meeting = model.meeting(id: meetingID), !meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    self.meetingID = meetingID
    workspaceGeneration = model.aiWorkspaceGeneration
    title = meeting.displayTitle
    createdAt = meeting.createdAt
    summary = meeting.summary
    privacy = meeting.effectivePrivacy
  }

  @MainActor
  func isCurrent(in model: MemoraModel) -> Bool {
    guard model.currentTeamID == nil, workspaceGeneration == model.aiWorkspaceGeneration,
          model.allowsRecordAccess(meetingID, purpose: .onDeviceAI),
          let meeting = model.meeting(id: meetingID) else { return false }
    return meeting.displayTitle == title && meeting.createdAt == createdAt
      && meeting.summary == summary && meeting.effectivePrivacy == privacy
  }
}
