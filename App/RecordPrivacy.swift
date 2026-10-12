import Foundation

struct RecordPrivacy: Codable, Hashable, Sendable {
  enum Classification: String, Codable, CaseIterable {
    case unknown, general, personal, sensitive
    var title: String {
      switch self {
      case .unknown: "未判定"
      case .general: "一般"
      case .personal: "個人・顧客情報"
      case .sensitive: "機密・要配慮情報"
      }
    }
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
  }
  var classification: Classification = .unknown
  var allowsCloudAI = false
  var allowsAutomaticAgentAccess = false
  var allowsAutomaticWebhook = false
  var allowsTeamSharing = false
  var updatedAt: Date = .now

  mutating func revokeExternalPermissions() {
    allowsCloudAI = false
    allowsAutomaticAgentAccess = false
    allowsAutomaticWebhook = false
    allowsTeamSharing = false
    updatedAt = .now
  }

  mutating func protect(_ sensitivity: SummarySensitivity) {
    let minimum: Classification = switch sensitivity {
    case .general: .unknown
    case .personal: .personal
    case .sensitive: .sensitive
    }
    guard minimum.rank > classification.rank else { return }
    classification = minimum
    allowsCloudAI = false
    allowsAutomaticAgentAccess = false
    allowsAutomaticWebhook = false
    allowsTeamSharing = false
    updatedAt = .now
  }
}
