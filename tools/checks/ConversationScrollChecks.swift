import Foundation

@main
enum ConversationScrollChecks {
  static func main() {
    var state = ConversationScrollState()
    precondition(state.update(.init(offset: 0, height: 300, contentHeight: 300), isUserDriven: false))
    precondition(state.update(.init(offset: 0, height: 300, contentHeight: 1_000), isUserDriven: false))
    precondition(state.followsLatest)
    // A held finger does not make a layout-only resize a scroll gesture.
    var held = ConversationScrollState()
    _ = held.update(.init(offset: 700, height: 300, contentHeight: 1_000), isUserDriven: false)
    precondition(held.update(.init(offset: 700, height: 180, contentHeight: 1_000), isUserDriven: true))
    precondition(held.followsLatest)
    precondition(held.update(.init(offset: 700, height: 180, contentHeight: 1_200), isUserDriven: true))
    precondition(held.followsLatest)
    // Opening the keyboard preserves following even before scrolling catches up.
    precondition(state.update(.init(offset: 700, height: 180, contentHeight: 1_000), isUserDriven: false))
    precondition(state.followsLatest)
    precondition(!state.update(.init(offset: 710, height: 180, contentHeight: 1_000), isUserDriven: false))
    precondition(state.followsLatest)
    _ = state.update(.init(offset: 700, height: 300, contentHeight: 1_000), isUserDriven: false)
    _ = state.update(.init(offset: 250, height: 300, contentHeight: 1_000), isUserDriven: true)
    precondition(!state.followsLatest && !state.contentArrived() && state.hasUnseenContent)
    precondition(!state.update(.init(offset: 250, height: 300, contentHeight: 1_100), isUserDriven: false))
    precondition(!state.followsLatest && state.hasUnseenContent)
    state.hasUnseenContent = false
    precondition(!state.update(.init(offset: 250, height: 180, contentHeight: 1_100), isUserDriven: false))
    precondition(!state.hasUnseenContent && !state.followsLatest)
    _ = state.update(.init(offset: 800, height: 300, contentHeight: 1_100), isUserDriven: true)
    precondition(state.followsLatest && !state.hasUnseenContent)
    // A person scrolls away during the same event as a row grows.
    precondition(!state.update(.init(offset: 200, height: 300, contentHeight: 1_200), isUserDriven: true))
    precondition(!state.followsLatest)
    state.follow()
    precondition(state.followsLatest && !state.hasUnseenContent && state.contentArrived())
    precondition(!state.update(.init(offset: .nan, height: 300, contentHeight: 1_200), isUserDriven: false))
    print("ConversationScrollChecks: passed (stream growth, lazy layout, manual reading, simultaneous scroll/resize, new-answer reset, invalid geometry)")
  }
}
