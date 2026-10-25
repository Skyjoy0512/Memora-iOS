import Foundation

enum SummaryPartScheduler {
  @MainActor
  static func collect(
    count: Int,
    maximumConcurrent: Int,
    operation: @escaping @MainActor @Sendable (Int) async -> Result<String, AIAnswerFailure>
  ) async -> Result<[String], AIAnswerFailure> {
    guard !Task.isCancelled else { return .failure(.cancelled) }
    guard count > 0 else { return .success([]) }
    let width = min(2, max(1, maximumConcurrent), count)
    return await withTaskGroup(of: (Int, Result<String, AIAnswerFailure>).self) { group in
      var notes = Array(repeating: "", count: count)
      var next = 0
      for index in 0..<width {
        group.addTask {
          guard !Task.isCancelled else { return (index, .failure(.cancelled)) }
          return (index, await operation(index))
        }
        next += 1
      }
      for await (index, result) in group {
        guard !Task.isCancelled else { group.cancelAll(); return .failure(.cancelled) }
        switch result {
        case .failure(let error):
          group.cancelAll()
          return .failure(error)
        case .success(let note): notes[index] = note
        }
        if next < count {
          let index = next
          group.addTask {
            guard !Task.isCancelled else { return (index, .failure(.cancelled)) }
            return (index, await operation(index))
          }
          next += 1
        }
      }
      return .success(notes)
    }
  }
}
