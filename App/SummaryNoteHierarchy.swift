import Foundation

/// Limits each merge request without discarding an older part of a long day.
/// A model that expands its notes stops the run rather than buying more loops.
enum SummaryNoteHierarchy {
  @MainActor
  static func reduce(_ original: [String], limit: Int,
                     merge: @MainActor ([String]) async -> Result<String, AIAnswerFailure>) async -> Result<[String], AIAnswerFailure> {
    var notes = original
    for _ in 0..<8 {
      guard !Task.isCancelled else { return .failure(.cancelled) }
      guard notes.count <= 512, limit > 0, notes.allSatisfy({ $0.count <= limit }) else {
        return .failure(.executionLimit)
      }
      let before = length(notes)
      if before <= limit { return .success(notes) }
      var groups: [[String]] = [], current: [String] = [], count = 0
      for note in notes {
        let added = note.count + (current.isEmpty ? 0 : 2)
        if !current.isEmpty, count + added > limit {
          groups.append(current)
          current = []
          count = 0
        }
        count += note.count + (current.isEmpty ? 0 : 2)
        current.append(note)
      }
      if !current.isEmpty { groups.append(current) }
      var reduced: [String] = []
      for group in groups {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        switch await merge(group) {
        case .failure(let failure): return .failure(failure)
        case .success(let note):
          guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                note.count <= limit else { return .failure(.executionLimit) }
          reduced.append(note)
        }
      }
      guard length(reduced) < before else { return .failure(.executionLimit) }
      notes = reduced
    }
    return length(notes) <= limit ? .success(notes) : .failure(.executionLimit)
  }

  private static func length(_ notes: [String]) -> Int {
    notes.reduce(0) { $0 + $1.count } + max(0, notes.count - 1) * 2
  }
}
