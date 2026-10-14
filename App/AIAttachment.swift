import Foundation

struct AIAttachment: Identifiable, Hashable, Sendable {
  var id: UUID
  var name: String
  var url: URL
}
