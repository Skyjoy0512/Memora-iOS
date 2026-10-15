import Foundation

enum ProjectTaskList {
  /// Membership comes from the project's current records, independent of who
  /// owns the task. Global and orphaned tasks never fill an empty project.
  static func select(from tasks: [MemoraTask], recordIDs: Set<UUID>, includeCompleted: Bool = false) -> [MemoraTask] {
    tasks.filter {
      $0.meetingID.map(recordIDs.contains) == true && (includeCompleted || !$0.isCompleted)
    }
  }
}
