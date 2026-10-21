import Foundation

@main
struct RootNavigationChecks {
  static func main() {
    let project = UUID()
    let meeting = UUID()
    let otherMeeting = UUID()
    let home: [LibraryRoute] = [.tasks]
    let projectPath: [LibraryRoute] = [.space(project)]
    let citationPath: [LibraryRoute] = [.space(project), .meetingCitation(meeting, 123)]
    precondition(RootNavigation.scope(tab: .library, path: citationPath, detailMeetingID: nil) == .file(meeting))
    precondition(RootNavigation.projectID(in: citationPath) == nil)
    precondition(RootTab.allCases == [.library, .home, .askAI])
    precondition(RootTab.allCases.map(\.title) == ["ライブラリ", "ジャーナル", "Ask AI"])
    precondition(RootTab.restored(from: "files") == .library)
    precondition(RootTab.restored(from: "library") == .library)
    precondition(RootTab.restored(from: "projects") == .library)
    precondition(RootTab.restored(from: "tasks") == .home)
    precondition(RootTab.restored(from: "journal") == .home)
    precondition(RootTab.restored(from: "unknown") == .library)
    precondition(RootTab.restored(from: "") == .library)
    precondition(LibrarySection.restored(from: nil) == .files)
    precondition(LibrarySection.restored(from: "unknown") == .files)
    precondition(LibrarySection.restored(from: "projects") == .projects)
    precondition(LibrarySection.restored(from: "files") == .files)

    for tab in RootTab.allCases {
      let path = RootNavigation.path(tab: tab, home: home, library: projectPath)
      let expected: [RootTab: [LibraryRoute]] = [.home: home, .library: projectPath, .askAI: []]
      precondition(path == expected[tab])
      precondition(RootNavigation.projectID(in: path) == (tab == .library ? project : nil))
    }
    precondition(RootNavigation.scope(tab: .library, path: projectPath, detailMeetingID: otherMeeting, detailTab: .home) == .space(project))
    precondition(RootNavigation.scope(tab: .library, path: projectPath + [.meeting(meeting)], detailMeetingID: nil) == .file(meeting))
    precondition(RootNavigation.scope(tab: .library, path: projectPath + [.transcript(meeting)], detailMeetingID: nil) == .file(meeting))
    precondition(RootNavigation.projectID(in: projectPath + [.meeting(meeting)]) == nil)
    precondition(RootNavigation.projectID(in: [.sharedProject("team")]) == nil)
    // Both library segments are global at their root; no previous project survives a pop.
    precondition(RootNavigation.projectID(in: []) == nil)
    precondition(RootNavigation.projectID(in: [.projectSources(project)]) == project)
    precondition(RootNavigation.projectID(in: [.projectSources(nil)]) == nil)
    precondition(RootNavigation.scope(tab: .library, path: [.projectSources(project)], detailMeetingID: nil) == .space(project))
    precondition(RootNavigation.scope(tab: .library, path: [.projectSources(nil)], detailMeetingID: nil) == .global)
    for tab in [RootTab.home, .library] {
      let related: [LibraryRoute] = [.space(project), .projectTasks(project)]
      precondition(RootNavigation.projectID(in: related) == project)
      precondition(RootNavigation.scope(tab: tab, path: related, detailMeetingID: nil) == .space(project))
      precondition(RootNavigation.scope(tab: .askAI, path: related, detailMeetingID: nil) == .global)
      precondition(RootNavigation.scope(tab: tab, path: related + [.meeting(meeting)], detailMeetingID: nil) == .file(meeting))
      precondition(RootNavigation.projectID(in: [.tasks]) == nil)
      for path: [LibraryRoute] in [[], [.projectSources(project)], [.projectChats(project)]] {
        precondition(RootNavigation.searchCoversScreen(tab: tab, path: path, isSearching: true, isSelectingFiles: false))
        precondition(!RootNavigation.searchCoversScreen(tab: tab, path: path, isSearching: false, isSelectingFiles: false))
      }
      for path: [LibraryRoute] in [[.projectSources(project), .projectSource(UUID())], [.meeting(meeting)], [.projectTasks(project)]] {
        precondition(!RootNavigation.searchCoversScreen(tab: tab, path: path, isSearching: true, isSelectingFiles: true))
      }
    }
    precondition(RootNavigation.searchCoversScreen(tab: .library, path: [], isSearching: false, isSelectingFiles: true))
    precondition(!RootNavigation.searchCoversScreen(tab: .home, path: [], isSearching: false, isSelectingFiles: true))
    precondition(!RootNavigation.searchCoversScreen(tab: .askAI, path: [], isSearching: true, isSelectingFiles: true))
    let documentPath = projectPath + [.document(UUID())]
    precondition(RootNavigation.projectID(in: documentPath) == nil)
    precondition(RootNavigation.scope(tab: .library, path: documentPath, detailMeetingID: nil) == .global)
    precondition(RootNavigation.scope(tab: .library, path: [], detailMeetingID: nil) == .global)
    precondition(RootNavigation.scope(tab: .library, path: [.meeting(meeting)], detailMeetingID: nil) == .file(meeting))
    precondition(RootNavigation.scope(tab: .askAI, path: projectPath, detailMeetingID: meeting) == .global)
    precondition(RootNavigation.scope(tab: .home, path: [], detailMeetingID: otherMeeting) == .global)
    precondition(RootNavigation.scope(tab: .home, path: home, detailMeetingID: meeting, detailTab: .home) == .file(meeting))
    precondition(RootNavigation.scope(tab: .askAI, path: [], detailMeetingID: meeting, detailTab: .askAI) == .file(meeting))
    print("RootNavigationChecks: passed (three tabs, legacy IDs, segment restoration, isolated stacks, recording destination, AI scopes)")
  }
}
