import Foundation

// These are dependency surfaces, never wrappers around real credentials or apps.
// The runner compiles the actual HTTP status mapper, prompt, providers and tools.
enum KeychainStore {
  static func string(forKey key: String) -> String? {
    ["ai.openAI", "ai.anthropic", "ai.deepSeek"].contains(key) ? "offline-fixture-key" : nil
  }
  static func has(_ key: String) -> Bool { string(forKey: key) != nil }
}
enum MemoraIntelligence { static let tokenAccount = "unconfigured-fixture" }
enum MemoraCreditMeter { static func observe(_ response: URLResponse) {} }
enum WebResearchClient { static let keyName = "unconfigured-brave-fixture" }
@MainActor final class GmailService {
  static let shared = GmailService()
  static let isConfigured = false
  var isConnected = false
}
@MainActor enum NotionService { static let isConfigured = false }
