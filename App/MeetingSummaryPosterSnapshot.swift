import Foundation

struct MeetingSummaryPosterSnapshot: Identifiable, Equatable {
  var id = UUID()
  var meetingID: UUID
  var workspaceGeneration: UUID
  var title: String
  var createdAt: Date
  var summary: String
  var privacy: RecordPrivacy

  // Presentation IDs are not revisions: an unrelated body update must not
  // re-render the same image, but edits and access changes must invalidate it.
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.meetingID == rhs.meetingID && lhs.workspaceGeneration == rhs.workspaceGeneration
      && lhs.title == rhs.title && lhs.createdAt == rhs.createdAt
      && lhs.summary == rhs.summary && lhs.privacy == rhs.privacy
  }

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
