import Foundation

extension AIPluginExecutionPolicy {
  // Availability is checked by the caller before resolving the selected tools.
  static func forSelection(pluginIDs: [String], plugins: [AIPlugin], onDevice: Bool) -> Self {
    var ids = plugins.reduce(into: Set<String>()) { $0.formUnion($1.toolIDs) }
    if !onDevice { ids.insert("memora:ask_user") }
    let records = Set(plugins.compactMap(\.recordID))
    return Self(pluginIDs: pluginIDs, toolIDs: ids,
      recordIDs: records,
      // A skill can add tools/instructions, never widen an explicit source set.
      limitsRecordReads: !records.isEmpty || !plugins.contains { $0.kind == .builtin || $0.kind == .skill || $0.id == "service:notion" },
      templateIDs: Set(plugins.compactMap(\.templateID)))
  }
}
