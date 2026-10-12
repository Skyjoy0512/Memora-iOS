import Foundation

@main
struct StandaloneRecordPrivacyChecks {
  static func main() throws {
    let parentID = UUID()
    let granted = RecordPrivacy(classification: .general, allowsCloudAI: true, allowsAutomaticAgentAccess: true)
    precondition(!RecordAccessPolicy.allowsRelated(nil, parentID: nil, parentPrivacy: nil, purpose: .cloudAI, inheritsParent: true))
    precondition(RecordAccessPolicy.allowsRelated(granted, parentID: nil, parentPrivacy: nil, purpose: .cloudAI))
    precondition(RecordAccessPolicy.allowsRelated(nil, parentID: parentID, parentPrivacy: granted, purpose: .cloudAI, inheritsParent: true))
    precondition(!RecordAccessPolicy.allowsRelated(RecordPrivacy(), parentID: parentID, parentPrivacy: granted, purpose: .cloudAI, inheritsParent: true))
    var parentDelivery = granted
    parentDelivery.allowsAutomaticWebhook = true
    parentDelivery.allowsTeamSharing = true
    precondition(RecordAccessPolicy.allowsRelated(nil, parentID: parentID, parentPrivacy: parentDelivery, purpose: .automaticWebhook, inheritsParent: true))
    precondition(!RecordAccessPolicy.allowsRelated(granted, parentID: parentID, parentPrivacy: parentDelivery, purpose: .automaticWebhook, inheritsParent: true))
    precondition(!RecordAccessPolicy.allowsRelated(granted, parentID: parentID, parentPrivacy: parentDelivery, purpose: .teamSharing, inheritsParent: true))
    precondition(!RecordAccessPolicy.allowsRelated(granted, parentID: parentID, parentPrivacy: nil, purpose: .cloudAI))
    precondition(!RecordAccessPolicy.allowsRelated(granted, parentID: parentID, parentPrivacy: RecordPrivacy(), purpose: .cloudAI))
    var privateParent = RecordPrivacy(classification: .sensitive, allowsCloudAI: true)
    precondition(!RecordAccessPolicy.allowsRelated(granted, parentID: parentID, parentPrivacy: privateParent, purpose: .cloudAI))
    var child = granted
    child.classification = .sensitive
    precondition(RecordAccessPolicy.allowsRelated(child, parentID: parentID, parentPrivacy: privateParent, purpose: .cloudAI))
    precondition(!RecordAccessPolicy.allowsRelated(child, parentID: parentID, parentPrivacy: privateParent, purpose: .automaticAgent))
    privateParent.revokeExternalPermissions()
    precondition(!RecordAccessPolicy.allowsRelated(child, parentID: parentID, parentPrivacy: privateParent, purpose: .cloudAI))
    let task = MemoraTask(id: UUID(), title: "単独のタスク", isCompleted: false, privacy: granted)
    let encoded = try JSONEncoder().encode(task)
    let restored = try JSONDecoder().decode(MemoraTask.self, from: encoded)
    precondition(restored.privacy == granted)
    var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    legacy.removeValue(forKey: "privacy")
    let old = try JSONDecoder().decode(MemoraTask.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.privacy == nil)
    for origin in [LifeLogOrigin.stationPass, .visit] {
      precondition(!AIJournalPrivacy.allowsReading(kind: .memo, origin: origin))
    }
    precondition(!AIJournalPrivacy.allowsReading(kind: .location, origin: .manual))
    print("StandaloneRecordPrivacyChecks: passed (legacy, grant, inheritance, orphan, parent floor, location denial)")
  }
}
