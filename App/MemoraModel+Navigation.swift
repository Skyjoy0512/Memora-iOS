import Foundation

extension MemoraModel {
  var activeNavigationPath: [LibraryRoute] {
    RootNavigation.path(tab: selectedTab, home: homePath, library: libraryPath)
  }

  func openProjects() {
    isSearchActive = false
    selectedTab = .library
    librarySection = .projects
    libraryPath = []
  }

  func openProject(_ id: UUID) {
    guard space(id: id) != nil else { return }
    isSearchActive = false
    selectedTab = .library
    librarySection = .projects
    libraryPath = [.space(id)]
    noteProjectUsed(id)
  }

  func openSharedProject(_ id: String) {
    isSearchActive = false
    selectedTab = .library
    librarySection = .projects
    libraryPath = [.sharedProject(id)]
  }

  func openTask(_ id: UUID) {
    isSearchActive = false
    pendingTaskEditID = id
    selectedTab = .home
    homePath = [.tasks]
  }

  func openSavedMeeting(_ id: UUID) {
    isSearchActive = false
    if let projectID = meeting(id: id)?.spaceID, space(id: projectID) != nil {
      openProject(projectID)
      libraryPath.append(.meeting(id))
    } else {
      selectedTab = .library
      librarySection = .files
      libraryPath = [.meeting(id)]
    }
  }
}
