import Foundation

@main struct SummaryHierarchyChecks {
  @MainActor static func main() async {
    for width in 1...4 {
      let gate = Gate()
      let source = Array("abcdefgh").map { String(repeating: String($0), count: 400) }
      let task = Task { await SummaryNoteHierarchy.reduce(source, limit: 1000, maximumConcurrent: width) {
        await gate.merge($0)
      } }
      var finished = 0
      while finished < 4 {
        await wait { gate.pending.count == min(width, 4 - finished) }
        for key in gate.pending.keys.sorted().reversed() { gate.finish(key, .success(key)); finished += 1 }
      }
      guard case .success(let value) = await task.value else { preconditionFailure() }
      precondition(value == ["ab", "cd", "ef", "gh"] && gate.maximumActive == width && gate.calls == 4)
    }
    let gate = Gate()
    let failed = Task { await SummaryNoteHierarchy.reduce(Array("abcdefgh").map { String(repeating: String($0), count: 400) },
      limit: 1000, maximumConcurrent: 2) { await gate.merge($0) } }
    await wait { gate.pending.count == 2 }
    gate.finish(gate.pending.keys.sorted()[0], .failure(.rateLimited))
    guard case .failure(.rateLimited) = await failed.value else { preconditionFailure() }
    precondition(gate.calls == 2 && gate.pending.isEmpty)
    var calls = 0
    let source = ["a", "b", "c", "d"].map { String(repeating: $0, count: 400) }
    let result = await SummaryNoteHierarchy.reduce(source, limit: 1000) { group in
      calls += 1
      precondition(group.joined(separator: "\n\n").count <= 1000)
      return .success(group.map { String($0.first!) }.joined())
    }
    guard case .success(let reduced) = result else { preconditionFailure("Hierarchy failed") }
    precondition(reduced.joined() == "abcd" && calls == 2)
    let small = await SummaryNoteHierarchy.reduce(["untouched"], limit: 1000) { _ in
      preconditionFailure("Short request made an extra call")
    }
    guard case .success(let original) = small else { preconditionFailure("Small notes failed") }
    precondition(original == ["untouched"])
    let expanding = await SummaryNoteHierarchy.reduce(source, limit: 1000) { group in
      .success(group.joined(separator: "\n\n"))
    }
    guard case .failure(.executionLimit) = expanding else { preconditionFailure("Expansion loop accepted") }
    let oversized = await SummaryNoteHierarchy.reduce([String(repeating: "x", count: 1001)], limit: 1000) { _ in
      preconditionFailure("Oversized note was sent")
    }
    guard case .failure(.executionLimit) = oversized else { preconditionFailure("Oversized note accepted") }
    let stopped = await Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      return await SummaryNoteHierarchy.reduce(source, limit: 1000) { _ in
        preconditionFailure("Cancelled hierarchy sent a request")
      }
    }.value
    guard case .failure(.cancelled) = stopped else { preconditionFailure("Cancellation ignored") }
    print("SummaryHierarchyChecks: PASS. All ordered inputs retained by fixture reducer; bounded merge groups; no extra short-input call; oversized/expanding output and cancellation stop. No live LLM quality claim.")
  }

  @MainActor static func wait(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() { precondition(.now < deadline); await Task.yield() }
  }
  @MainActor final class Gate {
    var pending: [String: CheckedContinuation<Result<String, AIAnswerFailure>, Never>] = [:]
    var maximumActive = 0
    var calls = 0
    func merge(_ group: [String]) async -> Result<String, AIAnswerFailure> {
      let key = group.map { String($0.first!) }.joined()
      return await withTaskCancellationHandler {
        await withCheckedContinuation {
          pending[key] = $0; calls += 1; maximumActive = max(maximumActive, pending.count)
        }
      } onCancel: { Task { @MainActor in self.finish(key, .failure(.cancelled)) } }
    }
    func finish(_ key: String, _ result: Result<String, AIAnswerFailure>) { pending.removeValue(forKey: key)?.resume(returning: result) }
  }
}
