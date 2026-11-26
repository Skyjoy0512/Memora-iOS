import Foundation

/// A user-approved request. The adapter must authenticate this scope and reserve
/// duration and storage on the server. User approval does not attest participant consent.
struct MeetingBotJoinRequest: Equatable, Sendable {
  let id: UUID
  let target: MeetingBotTarget
  let scope: MeetingBotJob.Scope
  let projectID: UUID?
  let maximumRecordingSeconds: Int
  let maximumAudioBytes: Int64
  let approvedAt: Date
  let submitBefore: Date

  init?(id: UUID, target: MeetingBotTarget, scope: MeetingBotJob.Scope, projectID: UUID?,
        maximumRecordingSeconds: Int, maximumAudioBytes: Int64, approvedAt: Date, submitBefore: Date) {
    guard maximumRecordingSeconds > 0, maximumAudioBytes > 0, approvedAt.timeIntervalSinceReferenceDate.isFinite,
          submitBefore.timeIntervalSinceReferenceDate.isFinite, approvedAt < submitBefore else { return nil }
    self.id = id
    self.target = target
    self.scope = scope
    self.projectID = projectID
    self.maximumRecordingSeconds = maximumRecordingSeconds
    self.maximumAudioBytes = maximumAudioBytes
    self.approvedAt = approvedAt
    self.submitBefore = submitBefore
  }

  func isApproved(at date: Date) -> Bool { approvedAt <= date && date < submitBefore }
}
