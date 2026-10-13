import Foundation

struct IntegrationUsage: Codable, Sendable {
  var day: Date
  var serverID: UUID
  var count: Int
}
