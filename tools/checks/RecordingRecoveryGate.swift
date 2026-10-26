import Foundation

@MainActor
final class RecordingRecoveryGate<Value> {
  private var continuation: CheckedContinuation<Value, Never>?

  func wait() async -> Value {
    await withCheckedContinuation { continuation = $0 }
  }

  func entered() async {
    while continuation == nil { await Task.yield() }
  }

  func resume(_ value: Value) {
    precondition(continuation != nil)
    let pending = continuation
    continuation = nil
    pending?.resume(returning: value)
  }
}
