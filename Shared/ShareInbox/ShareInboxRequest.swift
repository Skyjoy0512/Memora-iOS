import Foundation

struct ShareInboxRequest: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var projectID: UUID
  var createdAt = Date.now
  var items: [ShareInboxItem]
}
