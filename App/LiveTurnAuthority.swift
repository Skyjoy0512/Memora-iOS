import Foundation

/// Every microphone, model and playback callback must belong to the live turn.
struct LiveTurnAuthority {
  private(set) var sessionID: UUID?
  private(set) var revision = UUID()
  private(set) var responseID: UUID?

  mutating func begin() -> UUID {
    let id = UUID()
    sessionID = id
    revision = UUID()
    responseID = nil
    return id
  }

  mutating func attachResponse(_ id: UUID) {
    guard sessionID != nil else { return }
    revision = UUID()
    responseID = id
  }

  @discardableResult
  mutating func interrupt() -> UUID? {
    let previous = responseID
    revision = UUID()
    responseID = nil
    return previous
  }

  mutating func stop() {
    sessionID = nil
    interrupt()
  }

  func allows(session: UUID, revision: UUID) -> Bool {
    sessionID == session && self.revision == revision
  }
}
