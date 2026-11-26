import Foundation

/// The provider authenticates every operation and checks job ownership against
/// the authenticated workspace. The adapter must reject expired approval before
/// creating a job, enforce server quotas at admission, and emit recording only
/// after verified participant notice and consent. The join request ID is the
/// idempotency key for transport retries. A new attempt needs fresh approval.
protocol MeetingBotProvider: Sendable {
  func join(_ request: MeetingBotJoinRequest) async throws -> MeetingBotJob
  func updates(jobID: UUID, scope: MeetingBotJob.Scope, after sequence: UInt64) async throws -> [MeetingBotJob.Update]
  func stop(jobID: UUID, scope: MeetingBotJob.Scope) async throws

  /// The adapter writes verified audio to a caller-owned temporary file. It
  /// validates the ready audio and available storage before transfer, enforces the
  /// byte limit and digest during transfer, and removes partial data on failure.
  func downloadAudio(_ audio: MeetingBotJob.Audio, jobID: UUID, scope: MeetingBotJob.Scope, to destination: URL) async throws

  /// Acknowledge after Capture Coordinator commits the record. An identical
  /// acknowledgment can be retried without re-importing or re-joining.
  func acknowledgeImport(audioID: UUID, recordID: UUID, jobID: UUID, scope: MeetingBotJob.Scope) async throws
}
