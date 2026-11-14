import Foundation

enum RootNavigation {
  static func offersCapture(tab: RootTab, path: [LibraryRoute]) -> Bool {
    guard tab != .askAI else { return false }
    switch path.last {
    case nil, .space, .projectSources, .projectChats: return true
    default: return false
    }
  }

  static func searchCoversScreen(tab: RootTab, path: [LibraryRoute], isSearching: Bool, isSelectingFiles: Bool) -> Bool {
    guard tab != .askAI else { return false }
    if isSearching {
      switch path.last {
      case nil, .projectSources, .projectChats, .people, .documents: return true
      default: break
      }
    }
    return isSelectingFiles && tab == .library && path.isEmpty
  }

  static func path(tab: RootTab, home: [LibraryRoute], library: [LibraryRoute]) -> [LibraryRoute] {
    switch tab {
    case .home: home
    case .library: library
    case .askAI: []
    }
  }

  static func projectID(in path: [LibraryRoute]) -> UUID? {
    switch path.last {
    case .space(let id): id
    case .projectTasks(let id): id
    case .projectSources(let id), .projectChats(let id): id
    default: nil
    }
  }

  static func scope(tab: RootTab, path: [LibraryRoute], detailMeetingID: UUID?, detailTab: RootTab? = nil) -> AIQueryScope {
    // A detail can be pushed inside Ask AI without entering a value-based path.
    // Its origin also prevents an outgoing tab's detail leaking into the next tab.
    if let detailMeetingID, detailTab == tab { return .file(detailMeetingID) }
    guard tab != .askAI else { return .global }
    switch path.last {
    case .meeting(let id), .transcript(let id), .meetingCitation(let id, _): return .file(id)
    case .space(let id): return .space(id)
    case .projectTasks(let id): return .space(id)
    case .projectSources(let id), .projectChats(let id): return id.map(AIQueryScope.space) ?? .global
    default: return .global
    }
  }
}
