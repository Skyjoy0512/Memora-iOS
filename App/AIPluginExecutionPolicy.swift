import Foundation

struct AIPluginExecutionPolicy {
  var pluginIDs: [String]
  var toolIDs: Set<String>
  var recordIDs: Set<UUID>
  var limitsRecordReads: Bool
  var personID: UUID? = nil

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
    if let personID, id == "memora:read_person" {
      return (arguments["person_id"] as? String).flatMap(UUID.init(uuidString:)) == personID
    }
    if limitsRecordReads && id == "memora:read_record" {
      guard let text = arguments["id"] as? String, let id = UUID(uuidString: text), recordIDs.contains(id) else { return false }
    }
    return true
  }
}
