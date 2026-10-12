import Foundation

enum RootNavigation {
  static func path(tab: RootTab, home: [LibraryRoute], library: [LibraryRoute]) -> [LibraryRoute] {
    switch tab {
    case .home: home
    case .library: library
    case .askAI: []
    }
  }

  static func projectID(in path: [LibraryRoute]) -> UUID? {
    guard case .space(let id) = path.last else { return nil }
    return id
  }

  static func scope(tab: RootTab, path: [LibraryRoute], detailMeetingID: UUID?, detailTab: RootTab? = nil) -> AIQueryScope {
    // A detail can be pushed inside Ask AI without entering a value-based path.
    // Its origin also prevents an outgoing tab's detail leaking into the next tab.
    if let detailMeetingID, detailTab == tab { return .file(detailMeetingID) }
    guard tab != .askAI else { return .global }
    switch path.last {
    case .meeting(let id), .transcript(let id): return .file(id)
    case .space(let id): return .space(id)
    default: return .global
    }
  }
}
