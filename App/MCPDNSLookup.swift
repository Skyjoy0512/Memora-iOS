import Foundation

// getaddrinfo cannot be interrupted. Cancellation releases the awaiting request;
// its late resolver result must not resume that continuation a second time.
final class MCPDNSLookup: @unchecked Sendable {
  private var lock = NSLock()
  private var result: Bool?
  private var continuation: CheckedContinuation<Bool, Never>?

  func install(_ value: CheckedContinuation<Bool, Never>) {
    let completed = lock.withLock { () -> Bool? in
      if let result { return result }
      continuation = value
      return nil as Bool?
    }
    if let completed { value.resume(returning: completed) }
  }

  func finish(_ value: Bool) {
    let pending = lock.withLock {
      guard result == nil else { return nil as CheckedContinuation<Bool, Never>? }
      result = value
      let pending = continuation
      continuation = nil
      return pending
    }
    pending?.resume(returning: value)
  }
}
