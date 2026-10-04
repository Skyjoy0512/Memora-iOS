import Foundation

/// An always-on agent with its own name, role and instructions, after
/// OpenDots' "Dots": it works on a schedule or after a meeting, reads the
/// records and mail, and posts what it found to the Ask AI conversation. It
/// never changes data on its own; what it would do next comes back as a
/// suggestion the person can send. Runs only on the person's own API key.
struct ResidentAgent: Identifiable, Hashable, Codable {
  var id: UUID
  var name: String
  var role: String
  var instructions: String
  var symbol: MemoraIcon
  var trigger: ResidentTrigger
  var isEnabled = false
  /// Whether it may read what Ask AI remembers about the person.
  var usesMemory = true
  var lastRunAt: Date?
}
