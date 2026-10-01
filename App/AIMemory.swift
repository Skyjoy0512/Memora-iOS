import Foundation

/// One thing Ask AI keeps about the person across conversations, such as a
/// role, a preference, or who someone is. Only what the person said or
/// approved is kept; nothing is inferred behind their back.
struct AIMemory: Identifiable, Hashable, Codable {
  enum Origin: String, Codable {
    /// The person asked for it to be remembered, or added it in Settings.
    case told
    /// The agent proposed it and the person approved.
    case agent
  }

  var id: UUID
  var text: String
  var origin: Origin
  var createdAt: Date
}
