import Foundation

/// Somewhere a finished summary is sent: Zapier, Make, n8n, a Slack incoming
/// webhook, or any URL. The URL itself is kept in the keychain, since a
/// webhook URL works as a password.
struct WebhookEndpoint: Identifiable, Hashable, Codable {
  enum Format: String, Codable, CaseIterable, Identifiable {
    /// The whole record as structured JSON, for automation services.
    case json
    /// A readable message, for a Slack incoming webhook.
    case slack

    var id: Self { self }

    var label: String {
      switch self {
      case .json: "JSON（Zapier・Make・n8n など）"
      case .slack: "Slack"
      }
    }
  }

  var id: UUID
  var name: String
  var format: Format
  var isEnabled = true

  var keychainAccount: String { "webhook.\(id.uuidString)" }
}
