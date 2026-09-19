import Contacts
import Foundation

struct ContactSuggestion: Identifiable, Hashable {
  var id: String
  var name: String
}

/// Reads names from the address book so a recording can be tagged with the
/// people who were there.
enum ContactsService {
  static func requestAccess() async -> Bool {
    await withCheckedContinuation { continuation in
      CNContactStore().requestAccess(for: .contacts) { granted, _ in
        continuation.resume(returning: granted)
      }
    }
  }

  static func fetchContacts() async -> [ContactSuggestion] {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let keys: [CNKeyDescriptor] = [
          CNContactGivenNameKey as CNKeyDescriptor,
          CNContactFamilyNameKey as CNKeyDescriptor
        ]
        var results: [ContactSuggestion] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
          let name = "\(contact.familyName)\(contact.givenName)"
            .trimmingCharacters(in: .whitespaces)
          guard !name.isEmpty else { return }
          results.append(ContactSuggestion(id: contact.identifier, name: name))
        }
        continuation.resume(returning: results.sorted { $0.name < $1.name })
      }
    }
  }
}
