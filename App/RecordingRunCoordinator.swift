import Foundation

/// Guards one recording run from the moment the microphone is requested until
/// its audio is finalized. Every transition names the run it belongs to, so a
/// late callback, a double tap or a cancelled start cannot move a newer run.
///
/// This covers the capture/audio lifecycle. Committing the finished record to
/// the store remains the model's job; it begins after `markFinalizing`.
struct RecordingRunCoordinator: Equatable {
  enum Phase: Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case finalizing
    case saved
    case failed(String)
    case cancelled
  }

  private(set) var phase: Phase = .idle
  private(set) var runID: UUID?

  /// True while a run owns the microphone path.
  var isActive: Bool {
    switch phase {
    case .preparing, .recording, .stopping, .finalizing: true
    case .idle, .saved, .failed, .cancelled: false
    }
  }

  var isFailure: Bool {
    if case .failed = phase { return true }
    return false
  }

  /// Starts a new run unless one is already in flight. A finished, failed or
  /// cancelled run may be replaced.
  mutating func begin() -> UUID? {
    guard !isActive else { return nil }
    let id = UUID()
    runID = id
    phase = .preparing
    return id
  }

  func owns(_ id: UUID) -> Bool {
    runID == id && isActive
  }

  /// The microphone path is live and buffers may arrive for this run.
  @discardableResult
  mutating func markRecording(_ id: UUID) -> Bool {
    guard owns(id), phase == .preparing else { return false }
    phase = .recording
    return true
  }

  /// New input is cut off; accepted buffers still have to drain.
  @discardableResult
  mutating func beginStopping(_ id: UUID) -> Bool {
    guard owns(id), phase == .recording else { return false }
    phase = .stopping
    return true
  }

  /// Draining finished; the audio is being verified and committed.
  @discardableResult
  mutating func beginFinalizing(_ id: UUID) -> Bool {
    guard owns(id), phase == .stopping else { return false }
    phase = .finalizing
    return true
  }

  /// The audio is finalized. A later persistence step is outside this guard.
  @discardableResult
  mutating func markSaved(_ id: UUID) -> Bool {
    guard owns(id), phase == .finalizing else { return false }
    phase = .saved
    runID = nil
    return true
  }

  /// Ends the run with a recoverable failure. Allowed mid-flight so an
  /// overrun, capacity stop or interruption is not mistaken for success.
  @discardableResult
  mutating func fail(_ id: UUID, reason: String) -> Bool {
    guard owns(id) else { return false }
    phase = .failed(reason)
    runID = nil
    return true
  }

  @discardableResult
  mutating func cancel(_ id: UUID) -> Bool {
    guard owns(id) else { return false }
    phase = .cancelled
    runID = nil
    return true
  }

  /// Returns a finished run to idle so the recorder can be used again.
  mutating func reset() {
    guard !isActive else { return }
    phase = .idle
    runID = nil
  }
}
