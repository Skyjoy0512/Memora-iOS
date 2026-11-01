import Foundation

extension MemoraModel {
  func openSystemDestination(_ link: MemoraAppLink) {
    isSettingsPresented = false
    isAuthPresented = false
    isPaywallPresented = false
    isSearchActive = false
    isFileSelectionActive = false
    switch link {
    case .askAI:
      selectedTab = .askAI
      composerFocusRequest = UUID()
    case .journal:
      selectedTab = .home; homePath = []
    case .tasks:
      selectedTab = .home; homePath = [.tasks]; systemTaskFilterToday = false
    case .todayTasks:
      selectedTab = .home; homePath = [.tasks]; systemTaskFilterToday = true
    case .newMemo:
      selectedTab = .library; libraryPath = []
      sourceAddProjectID = nil
      sourceAddAsMemo = true
      isSourceAddPresented = true
    case .projects: openProjects()
    case .project(let id): openProject(id)
    }
  }
}
