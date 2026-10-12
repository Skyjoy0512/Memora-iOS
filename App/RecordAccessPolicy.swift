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

  static func allowsRelated(_ privacy: RecordPrivacy?, parentID: UUID?, parentPrivacy: RecordPrivacy?, purpose: Purpose,
                            inheritsParent: Bool = false) -> Bool {
    if parentID != nil {
      guard let parentPrivacy, allows(parentPrivacy, purpose: purpose) else { return false }
      if privacy == nil, inheritsParent { return true }
    }
    return allows(effectiveRelatedPrivacy(privacy ?? RecordPrivacy(), parent: parentPrivacy), purpose: purpose)
  }

  static func effectiveRelatedPrivacy(_ privacy: RecordPrivacy, parent: RecordPrivacy?) -> RecordPrivacy {
    var result = privacy
    if let parent {
      let sensitivity: SummarySensitivity = switch parent.classification {
      case .unknown, .general: .general
      case .personal: .personal
      case .sensitive: .sensitive
      }
      result.protect(sensitivity)
      result.updatedAt = privacy.updatedAt
    }
    return result
  }
}
