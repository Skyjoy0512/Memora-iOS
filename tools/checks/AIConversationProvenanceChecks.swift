import Foundation

@main
struct AIConversationProvenanceChecks {
  static func main() throws {
    let target = RecordPrivacyTarget.journal(UUID())
    let fingerprint = AIRecordFingerprint.make("原文")!
    let reference = AIRecordReference(target: target, fingerprint: fingerprint)
    let provenance = AIConversationProvenance(references: [reference], workspaceID: nil,
      memoryFingerprint: "memory")
    func reusable(_ provenance: AIConversationProvenance, workspace: String? = nil, memory: String = "memory",
                  granted: Bool = true, resolved: AIRecordReference? = reference) -> Bool {
      provenance.allowsReuse(workspaceID: workspace, memoryFingerprint: memory,
        resolve: { $0 == target ? resolved : nil }, allows: { _ in granted })
    }
    precondition(reusable(provenance))
    precondition(!reusable(provenance, granted: false))
    precondition(!reusable(provenance, workspace: "team"))
    precondition(!reusable(provenance, memory: "deleted memory"))
    precondition(!reusable(provenance, resolved: nil))
    precondition(!reusable(provenance, resolved: AIRecordReference(target: target, fingerprint: AIRecordFingerprint.make("編集後")!)))
    var unknown = provenance
    unknown.isComplete = false
    precondition(!reusable(unknown))
    unknown = provenance
    unknown.references = Array(repeating: reference, count: 257)
    precondition(!reusable(unknown))
    let reportID = UUID()
    let entry = AIConversationEntry(id: UUID(), question: "質問", answer: "回答", scopeLabel: "全体",
      createdAt: .now, cloudProvenance: provenance, webResearchReportID: reportID)
    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(AIConversationEntry.self, from: data)
    precondition(decoded.cloudProvenance == provenance)
    precondition(decoded.webResearchReportID == reportID)
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    legacy.removeValue(forKey: "cloudProvenance")
    legacy.removeValue(forKey: "webResearchReportID")
    let old = try JSONDecoder().decode(AIConversationEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.cloudProvenance == nil && old.answer == "回答")
    precondition(old.webResearchReportID == nil)
    legacy["cloudProvenance"] = ["isComplete": true]
    let malformed = try JSONDecoder().decode(AIConversationEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(malformed.cloudProvenance == nil && malformed.answer == "回答")
    precondition(AIRecordFingerprint.make(["key": "value"]) == AIRecordFingerprint.make(["key": "value"]))
    print("AIConversationProvenanceChecks: passed (grant, revoke, edit, missing source, workspace, memory, limit, legacy)")
  }
}
