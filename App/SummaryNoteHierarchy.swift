import Foundation

/// Limits each merge request without discarding an older part of a long day.
/// A model that expands its notes stops the run rather than buying more loops.
enum SummaryNoteHierarchy {
  @MainActor
  static func reduce(_ original: [String], limit: Int, maximumConcurrent: Int = 1,
                     measure: @escaping (String) -> Int = { $0.count },
                     merge: @escaping @MainActor ([String]) async -> Result<String, AIAnswerFailure>) async -> Result<[String], AIAnswerFailure> {
    var notes = original
    for _ in 0..<8 {
      guard !Task.isCancelled else { return .failure(.cancelled) }
      guard notes.count <= 512, limit > 0, notes.allSatisfy({ measure($0) <= limit }) else {
        return .failure(.executionLimit)
      }
      let before = length(notes, measure: measure)
      if before <= limit { return .success(notes) }
      var groups: [[String]] = [], current: [String] = [], count = 0
      for note in notes {
        let added = measure(note) + (current.isEmpty ? 0 : 2)
        if !current.isEmpty, count + added > limit {
          groups.append(current)
          current = []
          count = 0
        }
        count += measure(note) + (current.isEmpty ? 0 : 2)
        current.append(note)
      }
      if !current.isEmpty { groups.append(current) }
      let level = groups
      let result = await SummaryPartScheduler.collect(count: level.count, maximumConcurrent: maximumConcurrent) { index in
        guard !Task.isCancelled else { return .failure(.cancelled) }
        switch await merge(level[index]) {
        case .failure(let failure): return .failure(failure)
        case .success(let note):
          guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                measure(note) <= limit else { return .failure(.executionLimit) }
          return .success(note)
        }
      }
      let reduced: [String]
      switch result {
      case .failure(let failure): return .failure(failure)
      case .success(let value): reduced = value
      }
      guard length(reduced, measure: measure) < before else { return .failure(.executionLimit) }
      notes = reduced
    }
    return length(notes, measure: measure) <= limit ? .success(notes) : .failure(.executionLimit)
  }

  private static func length(_ notes: [String], measure: (String) -> Int) -> Int {
    notes.reduce(0) { $0 + measure($1) } + max(0, notes.count - 1) * 2
  }
}
