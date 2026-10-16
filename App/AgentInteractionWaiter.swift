import Foundation

/// Owns one user interaction without allowing an old task to dismiss its successor.
@MainActor
final class AgentInteractionWaiter<Value: Sendable> {
  private var pending: Pending?

  var pendingID: UUID? { pending?.id }

  func wait(id: UUID, present: () -> Void, dismiss: @escaping () -> Void) async -> Value? {
    guard !Task.isCancelled else { return nil }
    let token = UUID()
    let value: Value? = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else { continuation.resume(returning: nil); return }
        resolve(nil)
        pending = Pending(id: id, token: token, continuation: continuation, dismiss: dismiss)
        present()
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard self?.pending?.token == token else { return }
        self?.resolve(nil)
      }
    }
    return Task.isCancelled ? nil : value
  }

  @discardableResult
  func resolve(_ value: Value?, id: UUID? = nil) -> Bool {
    guard let current = pending, id == nil || current.id == id else { return false }
    pending = nil
    current.dismiss()
    current.continuation.resume(returning: value)
    return true
  }

  private struct Pending {
    var id: UUID
    var token: UUID
    var continuation: CheckedContinuation<Value?, Never>
    var dismiss: () -> Void
  }
}
