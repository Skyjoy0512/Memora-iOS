import Foundation
import Observation

/// Owns the long-running jobs a record goes through: transcription and
/// summarisation. The rules that decide whether a result may still be applied —
/// the record, its input, and the job's generation — live here, so the model
/// only writes results this service has approved, and every task reference is
/// released whichever way the job ends.
@MainActor
@Observable
final class ProcessingService {
  /// The run each record's job belongs to. Every run gets an identifier of its
  /// own that is never handed out again, so a job that finishes late can neither
  /// have its result applied over a newer one nor clear the newer job's record
  /// of running.
  private struct Run {
    var id: UUID
    var task: Task<Void, Never>
  }
  @ObservationIgnored private var runs: [UUID: Run] = [:]
  /// Records with a job running. The model persists this, so an interrupted job
  /// can be offered for retry after a restart.
  private(set) var activeIDs: Set<UUID> = []
  /// When each running job began, so the screen can show how long it has run.
  /// A job restored after a restart has no start time and shows none.
  private(set) var startedAt: [UUID: Date] = [:]
  /// Called whenever `activeIDs` changes, so the model can persist it.
  var onActiveIDsChanged: (() -> Void)?

  var activeIDStrings: [String] {
    activeIDs.map(\.uuidString)
  }

  /// Restores what was running when the app last stopped.
  func restoreInterrupted(_ ids: [String]) {
    activeIDs = Set(ids.compactMap(UUID.init(uuidString:)))
  }

  func isActive(_ id: UUID) -> Bool {
    activeIDs.contains(id)
  }

  /// Runs `work` for the record and hands its outcome to `apply` only while this
  /// is still the record's current job, and only if nothing cancelled it.
  func run<Outcome>(
    id: UUID,
    work: @escaping @MainActor () async -> Outcome,
    apply: @escaping @MainActor (Outcome) -> Void
  ) {
    runs[id]?.task.cancel()
    let token = UUID()
    setActive(id, active: true)
    startedAt[id] = .now

    let task = Task { [weak self] in
      let outcome = await work()
      guard let self else { return }
      defer { self.end(id, token: token) }
      guard !Task.isCancelled, self.runs[id]?.id == token else { return }
      apply(outcome)
    }
    runs[id] = Run(id: token, task: task)
  }

  /// Drops the record's job: its result must never be applied, and nothing keeps
  /// the task alive. A later run gets a fresh identifier, so this job finishing
  /// late cannot disturb it.
  func cancel(_ id: UUID) {
    runs[id]?.task.cancel()
    runs[id] = nil
    startedAt[id] = nil
    setActive(id, active: false)
  }

  /// A fingerprint of the transcript a summary was built from, so a result that
  /// raced an edit is not applied to the newer text. It hashes the words
  /// themselves, not their lengths, so an edit that keeps the length is caught.
  static func inputRevision(_ segments: [TranscriptSegment]) -> Int {
    var hasher = Hasher()
    hasher.combine(segments.count)
    for segment in segments {
      hasher.combine(segment.id)
      hasher.combine(segment.text)
      hasher.combine(segment.speaker)
      hasher.combine(segment.timestamp)
      hasher.combine(segment.endTime)
      hasher.combine(segment.speakerID)
      hasher.combine(segment.identificationStatus)
      hasher.combine(segment.speakerIsCertain)
    }
    return hasher.finalize()
  }

  /// Clears the slot unless a newer run has taken it in the meantime.
  private func end(_ id: UUID, token: UUID) {
    guard runs[id]?.id == token else { return }
    runs[id] = nil
    startedAt[id] = nil
    setActive(id, active: false)
  }

  private func setActive(_ id: UUID, active: Bool) {
    let changed = active ? activeIDs.insert(id).inserted : activeIDs.remove(id) != nil
    guard changed else { return }
    onActiveIDsChanged?()
  }
}
