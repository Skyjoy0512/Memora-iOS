import Foundation

enum TaskHierarchy {
  static func depths(in tasks: [MemoraTask]) -> [UUID: Int] {
    let parents = Dictionary(tasks.map { ($0.id, $0.relationships.parentID) }, uniquingKeysWith: { first, _ in first })
    var result: [UUID: Int] = [:]
    for task in tasks {
      var path: [UUID] = []
      var visited = Set<UUID>()
      var current: UUID? = task.id
      while let identifier = current, result[identifier] == nil,
            visited.insert(identifier).inserted, let parent = parents[identifier] {
        path.append(identifier)
        current = parent
      }
      var depth = current.flatMap { result[$0] }.map { $0 + 1 } ?? 0
      for identifier in path.reversed() {
        result[identifier] = depth
        depth += 1
      }
    }
    return result
  }

  static func eligibleParents(for taskID: UUID, in tasks: [MemoraTask]) -> [MemoraTask] {
    let children = Dictionary(grouping: tasks, by: { $0.relationships.parentID })
    var excluded: Set<UUID> = [taskID]
    var pending = [taskID]
    while let identifier = pending.popLast() {
      for child in children[identifier] ?? [] where excluded.insert(child.id).inserted {
        pending.append(child.id)
      }
    }
    return tasks.filter { !excluded.contains($0.id) }
  }

  static func canParent(_ taskID: UUID, under parentID: UUID?, tasks: [MemoraTask]) -> Bool {
    guard let parentID else { return true }
    let parents = Dictionary(tasks.map { ($0.id, $0.relationships.parentID) }, uniquingKeysWith: { first, _ in first })
    var visited: Set<UUID> = [taskID]
    var current: UUID? = parentID
    while let identifier = current {
      guard visited.insert(identifier).inserted, let parent = parents[identifier] else { return false }
      current = parent
    }
    return true
  }

  static func depth(of task: MemoraTask, in tasks: [MemoraTask]) -> Int {
    let parents = Dictionary(tasks.map { ($0.id, $0.relationships.parentID) }, uniquingKeysWith: { first, _ in first })
    var visited: Set<UUID> = [task.id]
    var current = task.relationships.parentID
    var depth = 0
    while let identifier = current, visited.insert(identifier).inserted, let parent = parents[identifier] {
      depth += 1
      current = parent
    }
    return depth
  }

  static func ordered(_ tasks: [MemoraTask]) -> [MemoraTask] {
    let identifiers = Set(tasks.map(\.id))
    let children = Dictionary(grouping: tasks, by: { $0.relationships.parentID })
    var output: [MemoraTask] = []
    var visited = Set<UUID>()
    func append(_ task: MemoraTask) {
      guard visited.insert(task.id).inserted else { return }
      output.append(task)
      for child in children[task.id] ?? [] { append(child) }
    }
    for task in tasks where task.relationships.parentID.map({ !identifiers.contains($0) }) ?? true { append(task) }
    for task in tasks { append(task) }
    return output
  }
}
