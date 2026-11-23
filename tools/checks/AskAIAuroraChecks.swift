import Foundation

@main
struct AskAIAuroraChecks {
  static func main() {
    var phase = AskAIAuroraPhase()
    let idle = AskAIAuroraPhase.Signal(replyID: nil)
    let first = UUID()
    let waiting = AskAIAuroraPhase.Signal(replyID: first)
    let streaming = AskAIAuroraPhase.Signal(replyID: first, hasText: true)
    let approval = AskAIAuroraPhase.Signal(replyID: first, isWaitingForPerson: true)
    precondition(!phase.isThinking(idle))
    precondition(phase.isThinking(waiting))
    phase.update(waiting)
    precondition(!phase.isThinking(approval))
    phase.update(approval)
    precondition(phase.isThinking(waiting))
    precondition(!phase.isThinking(streaming))
    phase.update(streaming)
    precondition(!phase.isThinking(waiting), "A tool turn clearing streamed text must not relight the same reply")
    phase.update(idle)
    precondition(!phase.isThinking(idle))
    let next = AskAIAuroraPhase.Signal(replyID: UUID())
    precondition(phase.isThinking(next))
    phase.update(next)
    precondition(!phase.isThinking(idle), "Completion, cancellation and errors all remove the active reply")

    var clock = AuroraAnimationState()
    let start = ContinuousClock.now
    func time(_ seconds: Double) -> ContinuousClock.Instant { start.advanced(by: .seconds(seconds)) }
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000_001 }
    precondition(clock.phase(at: time(10)) == 0)
    clock.setRunning(true, at: start)
    clock.setRunning(true, at: time(1))
    precondition(near(clock.phase(at: time(2)), 0.54))
    clock.setRunning(false, at: time(3))
    clock.setRunning(false, at: time(40))
    precondition(near(clock.phase(at: time(400)), 0.81))
    clock.setRunning(true, at: time(400))
    precondition(near(clock.phase(at: time(400)), 0.81))
    precondition(near(clock.phase(at: time(401)), 1.08))
    precondition(near(clock.phase(at: time(86_800)), (86_400 + 3) * 0.27))
    print("Ask AI Aurora: initial, approval, streaming latch, terminal/retry, pause/resume and long-duration clock passed")
  }
}
