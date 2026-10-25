import Foundation
import Synchronization

/// The SDK can send its initialized notification as soon as a reply is yielded,
/// before send() resumes on its actor. Publish the session before that yield,
/// and invalidate callbacks synchronously on disconnect/caller cancellation.
final class MCPHTTPResponseState: Sendable {
  private struct State: Sendable {
    var closed = false
    var sessionID: String?
    var active: Set<UUID> = []
  }
  private let state = Mutex(State())

  func checkOpen() throws {
    try state.withLock { if $0.closed { throw CancellationError() } }
  }

  func begin(_ id: UUID) throws -> String? {
    try state.withLock {
      guard !$0.closed else { throw CancellationError() }
      $0.active.insert(id)
      return $0.sessionID
    }
  }

  func end(_ id: UUID) { state.withLock { _ = $0.active.remove(id) } }

  func disconnect() { state.withLock { $0.closed = true; $0.sessionID = nil; $0.active.removeAll() } }

  func read(_ response: WebSourceHTTPDecoder.Response, complete: Bool, reader: MCPHTTPResponseReader, id: UUID) throws -> Bool {
    try state.withLock {
      guard !$0.closed, $0.active.contains(id) else { throw CancellationError() }
      if let sessionID = try MCPHTTPResponseReader.sessionID(response) {
        guard $0.sessionID == nil || $0.sessionID == sessionID else { throw MCPClientError.malformed }
        $0.sessionID = sessionID
      }
      return try reader.read(response, complete: complete)
    }
  }
}
