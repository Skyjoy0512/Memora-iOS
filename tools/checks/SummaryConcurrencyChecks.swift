import Foundation

@main @MainActor enum SummaryConcurrencyChecks {
  static func main() async {
    for width in 1...4 {
      let gate = Gate()
      let task = Task { await SummaryPartScheduler.collect(count: 8, maximumConcurrent: width) { index in
        await gate.operation(index)
      } }
      var completed = 0
      while completed < 8 {
        await wait { gate.pending.count == min(width, 8 - completed) }
        let active = gate.pending.keys.sorted().reversed()
        for index in active { gate.finish(index, .success("part\(index)")) }
        completed += active.count
      }
      guard case .success(let result) = await task.value else { preconditionFailure() }
      precondition(result == (0..<8).map { "part\($0)" })
      precondition(gate.maximumActive == width && gate.calls == 8)
    }
    let gate = Gate()
    let work = Task { await SummaryPartScheduler.collect(count: 20, maximumConcurrent: 4) { index in
      await gate.operation(index)
    } }
    await wait { gate.pending.count == 4 }
    gate.finish(0, .failure(.rateLimited))
    guard case .failure(.rateLimited) = await work.value else { preconditionFailure() }
    precondition(gate.calls == 4 && gate.pending.isEmpty)
    print("SummaryConcurrencyChecks: PASS; widths 1/2/3/4, bounded tasks, reverse arrival, exact order, 429 fail-stop, cancellation; no API timing")
  }
  static func wait(_ predicate: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !predicate() { precondition(ContinuousClock.now < deadline); await Task.yield() }
  }
  @MainActor final class Gate {
    var pending: [Int: CheckedContinuation<Result<String, AIAnswerFailure>, Never>] = [:]
    var maximumActive = 0
    var calls = 0
    func operation(_ index: Int) async -> Result<String, AIAnswerFailure> {
      await withTaskCancellationHandler {
        await withCheckedContinuation {
          pending[index] = $0; calls += 1; maximumActive = max(maximumActive, pending.count)
        }
      } onCancel: { Task { @MainActor in self.finish(index, .failure(.cancelled)) } }
    }
    func finish(_ index: Int, _ result: Result<String, AIAnswerFailure>) { pending.removeValue(forKey: index)?.resume(returning: result) }
  }
}
