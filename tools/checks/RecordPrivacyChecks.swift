import Foundation

@main
struct RecordPrivacyChecks {
  static func main() throws {
    var privacy = RecordPrivacy()
    precondition(RecordAccessPolicy.allows(privacy, purpose: .onDeviceAI))
    for purpose in [RecordAccessPolicy.Purpose.cloudAI, .automaticAgent, .automaticWebhook, .teamSharing] {
      precondition(!RecordAccessPolicy.allows(privacy, purpose: purpose))
    }
    precondition(RecordAccessPolicy.allows(privacy, purpose: .cloudAI, explicitCloudConsent: true))
    precondition(!privacy.allowsCloudAI)
    privacy.classification = .general
    privacy.allowsCloudAI = true
    privacy.allowsAutomaticAgentAccess = true
    privacy.allowsAutomaticWebhook = true
    privacy.allowsTeamSharing = true
    precondition(RecordAccessPolicy.allows(privacy, purpose: .automaticAgent))
    precondition(RecordAccessPolicy.allows(privacy, purpose: .automaticWebhook))
    privacy.protect(.sensitive)
    precondition(privacy.classification == .sensitive)
    precondition(!RecordAccessPolicy.allows(privacy, purpose: .automaticAgent))
    precondition(!RecordAccessPolicy.allows(privacy, purpose: .automaticWebhook))
    privacy.protect(.general)
    precondition(privacy.classification == .sensitive)
    let restored = try JSONDecoder().decode(RecordPrivacy.self, from: JSONEncoder().encode(privacy))
    precondition(restored == privacy)
    privacy.allowsAutomaticAgentAccess = true
    precondition(!RecordAccessPolicy.allows(privacy, purpose: .automaticAgent))
    print("RecordPrivacyChecks: passed (fail closed, one-shot consent, sticky classification, persistence)")
  }
}
