import Foundation

struct MeetingBotJob: Equatable, Sendable {
  struct Scope: Equatable, Sendable {
    let accountID: String
    let workspaceID: String?

    init?(accountID: String, workspaceID: String?) {
      guard Self.isID(accountID), workspaceID.map(Self.isID) != false else { return nil }
      self.accountID = accountID
      self.workspaceID = workspaceID
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      guard lhs.accountID.utf8.elementsEqual(rhs.accountID.utf8) else { return false }
      if let left = lhs.workspaceID, let right = rhs.workspaceID {
        return left.utf8.elementsEqual(right.utf8)
      }
      return lhs.workspaceID == nil && rhs.workspaceID == nil
    }

    private static func isID(_ id: String) -> Bool {
      let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
      return (1...256).contains(id.utf8.count) && !id.unicodeScalars.contains(where: forbidden.contains)
    }
  }

  struct Audio: Equatable, Sendable {
    enum Format: String, Sendable { case m4a, mp3, wav }

    let id: UUID
    let format: Format
    let byteCount: Int64
    let duration: TimeInterval
    let sha256: String

    init?(id: UUID, format: Format, byteCount: Int64, duration: TimeInterval, sha256: String) {
      guard byteCount > 0, duration.isFinite, duration > 0, sha256.utf8.count == 64,
            sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
      self.id = id
      self.format = format
      self.byteCount = byteCount
      self.duration = duration
      self.sha256 = sha256
    }
  }

  enum Phase: Equatable, Sendable {
    case requested, waitingForAdmission
    case awaitingConsent(admittedAt: Date)
    case recording, finalizing
    case audioReady(Audio)
    case imported(recordID: UUID)
    case denied, disconnected, stopped, expired, failed
  }

  struct Update: Equatable, Sendable {
    enum Event: Equatable, Sendable {
      case waitingForAdmission
      case admitted(Date)
      case recordingStarted(noticeConfirmedAt: Date, consentVerifiedAt: Date)
      case finalizing
      case audioReady(Audio)
      case audioExpired(audioID: UUID)
      case imported(audioID: UUID, recordID: UUID)
      case denied, disconnected, stopped, failed
    }

    let jobID: UUID
    let scope: Scope
    let sequence: UInt64
    let event: Event
  }

  let id: UUID
  let requestID: UUID
  let scope: Scope
  let projectID: UUID?
  let maximumRecordingSeconds: Int
  let maximumAudioBytes: Int64
  let acceptedAt: Date
  private(set) var lastSequence: UInt64 = 0
  private(set) var phase = Phase.requested

  init?(id: UUID, request: MeetingBotJoinRequest, acceptedAt: Date) {
    guard request.isApproved(at: acceptedAt) else { return nil }
    self.id = id
    requestID = request.id
    scope = request.scope
    projectID = request.projectID
    maximumRecordingSeconds = request.maximumRecordingSeconds
    maximumAudioBytes = request.maximumAudioBytes
    self.acceptedAt = acceptedAt
  }

  /// Apply authenticated events in order. A replay, gap, foreign job or
  /// impossible transition leaves all state intact.
  @discardableResult
  mutating func apply(_ update: Update) -> Bool {
    guard update.jobID == id, update.scope == scope, lastSequence < UInt64.max,
          update.sequence == lastSequence + 1 else { return false }
    let next: Phase
    switch (phase, update.event) {
    case (.requested, .waitingForAdmission):
      next = .waitingForAdmission
    case (.requested, .admitted(let time)), (.waitingForAdmission, .admitted(let time)):
      guard time.timeIntervalSinceReferenceDate.isFinite, acceptedAt <= time else { return false }
      next = .awaitingConsent(admittedAt: time)
    case (.awaitingConsent(let admittedAt), .recordingStarted(let notice, let consent)):
      guard admittedAt <= notice, notice <= consent, consent.timeIntervalSinceReferenceDate.isFinite else { return false }
      next = .recording
    case (.recording, .finalizing):
      next = .finalizing
    case (.finalizing, .audioReady(let audio)):
      guard audio.duration <= Double(maximumRecordingSeconds), audio.byteCount <= maximumAudioBytes else { return false }
      next = .audioReady(audio)
    case (.audioReady(let audio), .audioExpired(let audioID)):
      guard audio.id == audioID else { return false }
      next = .expired
    case (.audioReady(let audio), .imported(let audioID, let recordID)):
      guard audio.id == audioID else { return false }
      next = .imported(recordID: recordID)
    case (.requested, .denied), (.waitingForAdmission, .denied), (.awaitingConsent, .denied):
      next = .denied
    case (.waitingForAdmission, .disconnected), (.awaitingConsent, .disconnected), (.recording, .disconnected):
      next = .disconnected
    case (.requested, .stopped), (.waitingForAdmission, .stopped), (.awaitingConsent, .stopped):
      next = .stopped
    case (.requested, .failed), (.waitingForAdmission, .failed), (.awaitingConsent, .failed),
         (.recording, .failed), (.finalizing, .failed):
      next = .failed
    default:
      return false
    }
    phase = next
    lastSequence = update.sequence
    return true
  }
}
