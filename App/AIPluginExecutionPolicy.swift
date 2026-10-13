import Foundation

struct AIPluginExecutionPolicy {
  var pluginIDs: [String]
  var toolIDs: Set<String>
  var recordIDs: Set<UUID>
  var limitsRecordReads: Bool

  func permits(_ name: String, arguments: [String: Any]) -> Bool {
    let id = name.hasPrefix("mcp_") || name.hasPrefix("memora:") ? name : "memora:" + name
    guard toolIDs.contains(id) else { return false }
    if limitsRecordReads && id == "memora:read_record" {
      guard let text = arguments["id"] as? String, let id = UUID(uuidString: text), recordIDs.contains(id) else { return false }
    }
    return true
  }
}
