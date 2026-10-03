import Foundation

/// A caller ID check under way: the provider calls the person from
/// `callingFrom`, and they type `code` on the call's keypad.
struct CallerVerification: Hashable, Sendable {
  var code: String
  var callingFrom: String
}
