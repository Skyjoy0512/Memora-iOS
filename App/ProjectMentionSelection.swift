import Foundation

/// Ephemeral, validated selection. No permission grant is stored in conversation history.
struct ProjectMentionSelection: Equatable {
  static let readingTools: Set<String> = ["search_records", "read_record", "list_tasks"]
  var pluginIDs: [String]
  var toolNames: Set<String>
  var targets: Set<ProjectCitation.Target>?
  var guidance: String

  func permits(_ target: ProjectCitation.Target) -> Bool {
    targets?.contains(target) ?? true
  }
}
