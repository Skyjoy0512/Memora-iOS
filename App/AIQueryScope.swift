import Foundation

enum AIQueryScope: Hashable, Sendable {
  case file(UUID)
  case space(UUID)
  case global

  func includes(recordID: UUID, projectID: UUID?) -> Bool {
    switch self {
    case .file(let id): recordID == id
    case .space(let id): projectID == id
    case .global: true
    }
  }

  func includesTask(parentRecordID: UUID?, recordIDs: Set<UUID>) -> Bool {
    if self == .global { return true }
    return parentRecordID.map(recordIDs.contains) ?? false
  }
}
