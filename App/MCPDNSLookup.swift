import Foundation

// getaddrinfo cannot be interrupted. Cancellation releases the awaiting request;
// its late resolver result must not resume that continuation a second time.
final class MCPDNSLookup<Value: Sendable>: @unchecked Sendable {
  private var lock = NSLock()
  private var result: Value?
  private var continuation: CheckedContinuation<Value, Never>?

  func install(_ value: CheckedContinuation<Value, Never>) {
    let completed = lock.withLock { () -> Value? in
      if let result { return result }
      continuation = value
      return nil
    }
    if let completed { value.resume(returning: completed) }
  }

  func finish(_ value: Value) {
    let pending = lock.withLock {
      guard result == nil else { return nil as CheckedContinuation<Value, Never>? }
      result = value
      let pending = continuation
      continuation = nil
      return pending
    }
    pending?.resume(returning: value)
  }
}
