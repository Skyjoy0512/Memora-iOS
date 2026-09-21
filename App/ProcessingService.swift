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
  /// The generation each record's job belongs to. A newer request bumps it, so
  /// an older result cannot overwrite a newer one.
  @ObservationIgnored private var generations: [UUID: Int] = [:]
  @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
  /// Records with a job running. The model persists this, so an interrupted job
  /// can be offered for retry after a restart.
  private(set) var activeIDs: Set<UUID> = []
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
    let generation = begin(id)
    tasks[id]?.cancel()
    tasks[id] = Task { [weak self] in
      let outcome = await work()
      guard let self else { return }
      defer { self.end(id, generation: generation) }
      guard !Task.isCancelled, self.generations[id] == generation else { return }
      apply(outcome)
    }
  }

  /// Drops the record's job: its result must never be applied, and nothing keeps
  /// the task alive.
  func cancel(_ id: UUID) {
    tasks[id]?.cancel()
    tasks[id] = nil
    generations[id] = nil
    setActive(id, active: false)
  }

  /// A cheap fingerprint of the transcript a summary was built from, so a result
  /// that raced an edit is not applied to the newer text.
  static func inputRevision(_ segments: [TranscriptSegment]) -> Int {
    var hasher = Hasher()
    hasher.combine(segments.count)
    for segment in segments {
      hasher.combine(segment.id)
      hasher.combine(segment.text.count)
      hasher.combine(segment.speaker.count)
    }
    return hasher.finalize()
  }

  private func begin(_ id: UUID) -> Int {
    let next = (generations[id] ?? 0) + 1
    generations[id] = next
    setActive(id, active: true)
    return next
  }

  /// Clears the slot unless a newer job has taken it in the meantime.
  private func end(_ id: UUID, generation: Int) {
    guard generations[id] == generation else { return }
    tasks[id] = nil
    setActive(id, active: false)
  }

  private func setActive(_ id: UUID, active: Bool) {
    let changed = active ? activeIDs.insert(id).inserted : activeIDs.remove(id) != nil
    guard changed else { return }
    onActiveIDsChanged?()
  }
}
