import Foundation

// Hold a real suspension point without a clock-based race or external request.
actor HTTPResponseGate {
  private var arrived = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var pending: CheckedContinuation<Void, Never>?

  func pause() async {
    arrived = true
    waiter?.resume()
    waiter = nil
    await withCheckedContinuation { pending = $0 }
  }

  func waitForRequest() async {
    if arrived { return }
    await withCheckedContinuation { waiter = $0 }
  }

  func release() {
    pending?.resume()
    pending = nil
  }
}
