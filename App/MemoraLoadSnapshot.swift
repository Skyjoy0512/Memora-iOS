import Foundation

/// Content belongs to a key; a request token rejects late results, including retries.
struct MemoraLoadSnapshot<Key: Equatable, Value> {
  private(set) var key: Key?
  private(set) var value: Value?
  private(set) var state = MemoraLoadingState.idle
  private(set) var failure: String?
  private var requestID: UUID?
  private var settledState = MemoraLoadingState.idle
  var activityID: UUID? { requestID }

  func value(for key: Key) -> Value? { self.key == key ? value : nil }
  func state(for key: Key) -> MemoraLoadingState { self.key == key ? state : .idle }

  mutating func begin(_ key: Key) -> UUID {
    if self.key != key { value = nil; settledState = .idle }
    self.key = key
    failure = nil
    state = value == nil ? .loading : .refreshing
    let token = UUID()
    requestID = token
    return token
  }

  mutating func finish(_ value: Value, isEmpty: Bool, token: UUID) {
    guard requestID == token else { return }
    self.value = value
    state = isEmpty ? .empty : .loaded
    settledState = state
    failure = nil
    requestID = nil
  }

  mutating func fail(_ message: String, token: UUID) {
    guard requestID == token else { return }
    failure = message
    state = .failed
    requestID = nil
  }

  mutating func cancel(_ token: UUID) {
    guard requestID == token else { return }
    requestID = nil
    failure = nil
    state = value == nil ? .idle : settledState
  }
}
