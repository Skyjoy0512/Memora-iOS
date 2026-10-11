import Foundation

enum RecordAccessPolicy {
  enum Purpose {
    case cloudAI, automaticAgent, automaticWebhook, teamSharing
  }
  static let refusal = "この記録は外部送信が許可されていません。記録の「プライバシーと外部送信」で確認してください。"

  static func allows(_ privacy: RecordPrivacy, purpose: Purpose, explicitCloudConsent: Bool = false) -> Bool {
    if purpose == .cloudAI, explicitCloudConsent { return true }
    guard privacy.classification != .unknown else { return false }
    switch purpose {
    case .cloudAI: return privacy.allowsCloudAI
    case .automaticAgent: return privacy.allowsCloudAI && privacy.allowsAutomaticAgentAccess
    case .automaticWebhook: return privacy.allowsAutomaticWebhook
    case .teamSharing: return privacy.allowsTeamSharing
    }
  }
}
