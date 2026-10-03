import Contacts
import Foundation

/// Reads the device's contacts that have a phone number, on the device only.
enum CallContactsLoader {
  static var isAuthorized: Bool {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if #available(iOS 18.0, *), status == .limited { return true }
    return status == .authorized
  }

  static func load() async -> [CallContact] {
    guard isAuthorized else { return [] }
    return await Task.detached(priority: .userInitiated) { () -> [CallContact] in
      let keys = [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey
      ] as [CNKeyDescriptor]
      let request = CNContactFetchRequest(keysToFetch: keys)
      request.sortOrder = .userDefault
      var contacts: [CallContact] = []
      try? CNContactStore().enumerateContacts(with: request) { contact, _ in
        guard let phone = contact.phoneNumbers.first?.value.stringValue else { return }
        let name = [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined(separator: " ")
        contacts.append(CallContact(
          id: contact.identifier,
          name: name.isEmpty ? (contact.organizationName.isEmpty ? phone : contact.organizationName) : name,
          number: phone
        ))
      }
      return contacts
    }.value
  }
}
