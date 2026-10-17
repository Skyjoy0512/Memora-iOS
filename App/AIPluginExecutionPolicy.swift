import Foundation

struct AIPluginExecutionPolicy: Equatable {
  var pluginIDs: [String]
  var toolIDs: Set<String>
  var recordIDs: Set<UUID>
  var limitsRecordReads: Bool
  var personID: UUID? = nil
  var templateIDs: Set<UUID> = []
  var personTaskIDs: Set<UUID> = []
  var personJournalIDs: Set<UUID> = []

  func includesTask(id: UUID, meetingID: UUID?) -> Bool {
    !limitsRecordReads || personTaskIDs.contains(id) || meetingID.map(recordIDs.contains) == true
  }

  static func selectionIDs(_ explicit: [String], webSearchRequested: Bool) -> [String] {
    guard !explicit.isEmpty else { return [] }
    var result = explicit
    let webID = "tool:memora:search_web"
    if webSearchRequested && !result.contains(webID) { result.append(webID) }
    return result
  }

  func permits(_ name: String, arguments: [String: Any]) -> Bool {
    let id = name.hasPrefix("mcp_") || name.hasPrefix("memora:") ? name : "memora:" + name
    guard toolIDs.contains(id) else { return false }
    if !templateIDs.isEmpty, ["memora:create_document", "memora:create_slides"].contains(id) {
      guard let text = arguments["template_id"] as? String, let id = UUID(uuidString: text), templateIDs.contains(id) else { return false }
    }
    if let personID, id == "memora:read_person" {
      return (arguments["person_id"] as? String).flatMap(UUID.init(uuidString:)) == personID
    }
    if limitsRecordReads && id == "memora:read_record" {
      guard let text = arguments["id"] as? String, let id = UUID(uuidString: text),
            recordIDs.contains(id) || (personID != nil && personJournalIDs.contains(id)) else { return false }
    }
    return true
  }
}
