import Foundation

/// A contact with a number to call, read from the device's contacts.
struct CallContact: Identifiable, Hashable, Sendable {
  var id: String
  var name: String
  var number: String

  var initials: String {
    String(name.split(separator: " ").prefix(2).compactMap(\.first))
  }
}
