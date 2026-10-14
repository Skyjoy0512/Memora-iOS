import Foundation

enum MemoraAppLink: Equatable, Sendable {
  case askAI, journal, tasks, todayTasks, newMemo, projects, project(UUID)

  var url: URL {
    let path: String
    switch self {
    case .askAI: path = "ask-ai"
    case .journal: path = "journal"
    case .tasks: path = "tasks"
    case .todayTasks: path = "today-tasks"
    case .newMemo: path = "new-memo"
    case .projects: path = "projects"
    case .project(let id): path = "project/" + id.uuidString
    }
    return URL(string: "memora://" + path)!
  }

  init?(url: URL) {
    guard url.scheme?.lowercased() == "memora", url.user == nil, url.password == nil, url.port == nil,
          url.query == nil, url.fragment == nil else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    switch url.host?.lowercased() {
    case "ask-ai" where path.isEmpty: self = .askAI
    case "journal" where path.isEmpty: self = .journal
    case "tasks" where path.isEmpty: self = .tasks
    case "today-tasks" where path.isEmpty: self = .todayTasks
    case "new-memo" where path.isEmpty: self = .newMemo
    case "projects" where path.isEmpty: self = .projects
    case "project" where path.count == 1:
      guard let id = UUID(uuidString: path[0]) else { return nil }; self = .project(id)
    default: return nil
    }
  }
}
