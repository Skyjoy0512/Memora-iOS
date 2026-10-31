import Foundation

// A queued OS request is not permission to start a billable network request.
@MainActor
final class SummaryExecutionGate {
  enum Permission: Equatable, Sendable {
    case continued, foreground, stopped
  }

  private var permission: Permission?
  private var waiters: [UUID: CheckedContinuation<Permission, Never>] = [:]

  func wait() async -> Permission {
    guard !Task.isCancelled else { return .stopped }
    if let permission { return permission }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled { continuation.resume(returning: .stopped) }
        else if let permission { continuation.resume(returning: permission) }
        else { waiters[id] = continuation }
      }
    } onCancel: {
      Task { @MainActor in self.waiters.removeValue(forKey: id)?.resume(returning: .stopped) }
    }
  }

  func resolve(_ permission: Permission) {
    guard self.permission != .stopped else { return }
    self.permission = permission
    let pending = waiters.values
    waiters.removeAll()
    for waiter in pending { waiter.resume(returning: permission) }
  }
}
