import Foundation

actor SourceProcessingQueue {
  static let shared = SourceProcessingQueue()
  private var isBusy = false

  func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    // OCR and audio decoding share a bounded working set, including multiple
    // files arriving from the extension and a picker at the same time.
    while isBusy {
      try Task.checkCancellation()
      try await Task.sleep(for: .milliseconds(100))
    }
    try Task.checkCancellation()
    isBusy = true
    defer { isBusy = false }
    return try await operation()
  }
}
