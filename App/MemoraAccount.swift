import Foundation

/// A signed-in Memora account.
///
/// Signing in is optional. Recording, transcription, and organizing all work
/// without an account; the account only adds sync and Plus.
struct MemoraAccount: Codable, Hashable {
  var displayName: String
  var email: String
  var provider: AuthProvider
  var createdAt: Date
}
