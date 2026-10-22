import Foundation

/// A synchronous UI operation can own its error alert without a second root
/// alert dismissing its form. Never keep this scope open across an await.
@MainActor
final class PersistenceFailurePresentation {
  private var localDepth = 0
  var shouldPresentGlobally: Bool { localDepth == 0 }

  func locallyHandled<Value>(_ operation: () throws -> Value) rethrows -> Value {
    localDepth += 1
    defer { localDepth -= 1 }
    return try operation()
  }
}
