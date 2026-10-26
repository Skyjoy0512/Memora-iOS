import Foundation

enum RecordAccessPolicy {
  enum Purpose {
    case cloudAI, automaticAgent, automaticWebhook, teamSharing, onDeviceAI
  }
  static let refusal = "この記録は外部送信が許可されていません。記録の「プライバシーと外部送信」で確認してください。"
  static let personRefusal = "人物情報を参照できません。人物詳細の「その他」→「プライバシーと外部送信」で対象と許可を確認してください。関連する会議・タスク・メモには別の許可が必要です。"

  static func allowsSummarySubmission(_ privacy: RecordPrivacy) -> Bool {
    if privacy.blocksOneTimeCloudSummary == true { return false }
    // Unclassified records may be sent by an explicit, one-time instruction.
    // A classified record with cloud use disabled remains prohibited.
    return privacy.classification == .unknown || privacy.allowsCloudAI
  }

  static func allowsSummary(_ privacy: RecordPrivacy, userInitiated: Bool) -> Bool {
    userInitiated ? allowsSummarySubmission(privacy) : allows(privacy, purpose: .cloudAI)
  }

  static func allows(_ privacy: RecordPrivacy, purpose: Purpose, explicitCloudConsent: Bool = false) -> Bool {
    if purpose == .onDeviceAI { return true }
    if purpose == .cloudAI, explicitCloudConsent { return true }
    guard privacy.classification != .unknown else { return false }
    switch purpose {
    case .cloudAI: return privacy.allowsCloudAI
    case .automaticAgent: return privacy.allowsCloudAI && privacy.allowsAutomaticAgentAccess
    case .automaticWebhook: return privacy.allowsAutomaticWebhook
    case .teamSharing: return privacy.allowsTeamSharing
    case .onDeviceAI: return true
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
