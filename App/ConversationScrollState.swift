import Foundation

struct ConversationScrollState: Equatable {
  var followsLatest = true
  var hasUnseenContent = false
  private var previous: Viewport?

  struct Viewport: Equatable {
    var offset: Double
    var height: Double
    var contentHeight: Double
  }

  mutating func update(_ viewport: Viewport, isUserDriven: Bool) -> Bool {
    guard [viewport.offset, viewport.height, viewport.contentHeight].allSatisfy(\.isFinite) else { return false }
    let layoutChanged = previous?.contentHeight != viewport.contentHeight || previous?.height != viewport.height
    previous = viewport
    // Keyboard resizing and lazy row measurement must not change reading intent.
    if !isUserDriven { return layoutChanged && followsLatest }
    followsLatest = viewport.offset + viewport.height >= viewport.contentHeight - 80
    if followsLatest { hasUnseenContent = false }
    return false
  }

  mutating func contentArrived() -> Bool {
    if !followsLatest { hasUnseenContent = true }
    return followsLatest
  }

  mutating func follow() { followsLatest = true; hasUnseenContent = false }
}
