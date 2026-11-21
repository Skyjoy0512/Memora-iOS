import Foundation

struct ConversationScrollState: Equatable {
  var followsLatest = true
  var hasUnseenContent = false
  private var previous: Viewport?

  struct Viewport: Equatable {
    var offset: Double
    var height: Double
    var contentHeight: Double
    var bottomInset: Double = 0

    var distanceToLatest: Double { contentHeight + bottomInset - offset - height }
  }

  mutating func update(_ viewport: Viewport, isUserDriven: Bool, isStreaming: Bool = false) -> Bool {
    guard [viewport.offset, viewport.height, viewport.contentHeight, viewport.bottomInset].allSatisfy(\.isFinite) else {
      return false
    }
    let contentGrew = previous.map { viewport.contentHeight > $0.contentHeight } ?? false
    let viewportChanged = previous?.height != viewport.height || previous?.bottomInset != viewport.bottomInset
    let layoutChanged = viewportChanged || previous?.contentHeight != viewport.contentHeight
    let offsetChanged = previous.map { $0.offset != viewport.offset } ?? true
    previous = viewport
    // Keyboard resizing and lazy row measurement must not change reading intent.
    if !isUserDriven || (layoutChanged && !offsetChanged) {
      if contentGrew && !followsLatest { hasUnseenContent = true }
      guard layoutChanged && followsLatest else { return false }
      // Keep the visible tail in place until enough text has arrived for
      // another line. A keyboard or footer resize still settles the viewport.
      return viewportChanged || !isStreaming || (contentGrew && !isUserDriven && viewport.distanceToLatest >= 32)
    }
    followsLatest = viewport.distanceToLatest <= 80
    if followsLatest { hasUnseenContent = false }
    return false
  }

  mutating func contentArrived() -> Bool {
    if !followsLatest { hasUnseenContent = true }
    return followsLatest
  }

  mutating func follow() { followsLatest = true; hasUnseenContent = false }
}
