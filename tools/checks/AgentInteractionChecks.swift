import Foundation

@main
@MainActor
struct AgentInteractionChecks {
  static func main() async {
    let waiter = AgentInteractionWaiter<Bool>()
    var shown = 0
    var hidden = 0
    var writes = 0
    let firstID = UUID()
    let accepted = Task { @MainActor in
      await waiter.wait(id: firstID) { shown += 1 } dismiss: { hidden += 1 }
    }
    await installed(firstID, in: waiter)
    precondition(!waiter.resolve(true, id: UUID()))
    precondition(waiter.pendingID == firstID && hidden == 0)
    precondition(waiter.resolve(true, id: firstID))
    precondition(!waiter.resolve(true, id: firstID))
    let acceptedValue = await accepted.value
    precondition(acceptedValue == true && shown == 1 && hidden == 1)

    let deniedID = UUID()
    let denied = Task { @MainActor in
      await waiter.wait(id: deniedID) {} dismiss: { hidden += 1 }
    }
    await installed(deniedID, in: waiter)
    waiter.resolve(false)
    let deniedValue = await denied.value
    precondition(deniedValue == false && hidden == 2)

    let cancelledID = UUID()
    let cancelled = Task { @MainActor in
      let approved = await waiter.wait(id: cancelledID) {} dismiss: { hidden += 1 }
      if approved == true { writes += 1 }
      return approved
    }
    await installed(cancelledID, in: waiter)
    cancelled.cancel()
    let cancelledValue = await cancelled.value
    precondition(cancelledValue == nil && waiter.pendingID == nil && hidden == 3 && writes == 0)

    // Approval can win the UI race just before task cancellation is observed.
    let raceID = UUID()
    let race = Task { @MainActor in
      if await waiter.wait(id: raceID, present: {}, dismiss: {}) == true { writes += 1 }
    }
    await installed(raceID, in: waiter)
    waiter.resolve(true, id: raceID)
    race.cancel()
    await race.value
    precondition(writes == 0)

    let oldID = UUID(), newID = UUID()
    let old = Task { @MainActor in await waiter.wait(id: oldID, present: {}, dismiss: {}) }
    await installed(oldID, in: waiter)
    let replacement = Task { @MainActor in await waiter.wait(id: newID, present: {}, dismiss: {}) }
    await installed(newID, in: waiter)
    let oldValue = await old.value
    precondition(oldValue == nil)
    old.cancel()
    precondition(!waiter.resolve(true, id: oldID) && waiter.pendingID == newID)
    waiter.resolve(true, id: newID)
    let replacementValue = await replacement.value
    precondition(replacementValue == true)

    // A cancellation callback queued for the previous wait must not dismiss a
    // successor, even when a caller reuses the presentation ID.
    let reusedID = UUID()
    let previous = Task { @MainActor in await waiter.wait(id: reusedID, present: {}, dismiss: {}) }
    await installed(reusedID, in: waiter)
    let successor = Task { @MainActor in await waiter.wait(id: reusedID, present: {}, dismiss: {}) }
    previous.cancel()
    let previousValue = await previous.value
    precondition(previousValue == nil)
    // Both callbacks have finished before testing the successor's decision.
    for _ in 0..<20 { await Task.yield() }
    precondition(waiter.pendingID == reusedID)
    waiter.resolve(true, id: reusedID)
    let successorValue = await successor.value
    precondition(successorValue == true)

    // A stopped task entering late may not replace the current card.
    let currentID = UUID()
    let current = Task { @MainActor in await waiter.wait(id: currentID, present: {}, dismiss: {}) }
    await installed(currentID, in: waiter)
    let stopped = Task { @MainActor in
      await waiter.wait(id: UUID()) { shown += 1 } dismiss: { hidden += 1 }
    }
    stopped.cancel()
    let stoppedValue = await stopped.value
    precondition(stoppedValue == nil && waiter.pendingID == currentID && shown == 1 && hidden == 3)
    waiter.resolve(false)
    let currentValue = await current.value
    precondition(currentValue == false)

    let questions = AgentInteractionWaiter<[String]>()
    let questionID = UUID()
    let answers = Task { @MainActor in await questions.wait(id: questionID, present: {}, dismiss: {}) }
    await installed(questionID, in: questions)
    precondition(!questions.resolve(["stale"], id: UUID()))
    questions.resolve(["担当A", "次回確認"], id: questionID)
    let answerValue = await answers.value
    precondition(answerValue == ["担当A", "次回確認"])

    let result = await withTaskGroup(of: Bool.self) { group in
      let childID = UUID()
      group.addTask { await waitForQuestion(questions, id: childID) }
      await installed(childID, in: questions)
      group.cancelAll()
      return await group.next()
    }
    precondition(result == true && questions.pendingID == nil)

    for _ in 0..<100 {
      let id = UUID()
      let task = Task { @MainActor in await waiter.wait(id: id, present: {}, dismiss: {}) }
      await installed(id, in: waiter)
      task.cancel()
      waiter.resolve(true, id: id)
      let value = await task.value
      precondition(value == nil)
    }
    precondition(waiter.pendingID == nil)
    print("Agent interaction passed: approval/questions, cancellation, replacement, stale IDs, no writes after cancellation")
  }

  private static func installed<T>(_ id: UUID, in waiter: AgentInteractionWaiter<T>) async {
    for _ in 0..<10_000 {
      if waiter.pendingID == id { return }
      await Task.yield()
    }
    preconditionFailure("Interaction did not register")
  }

  private static func waitForQuestion(_ waiter: AgentInteractionWaiter<[String]>, id: UUID) async -> Bool {
    let value = await waiter.wait(id: id, present: {}, dismiss: {})
    return value == nil
  }
}
