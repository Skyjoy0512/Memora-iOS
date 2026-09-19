import Foundation

/// Someone a recording can be tagged with, like a face in Photos. It may come
/// from the address book or be created here.
struct Person: Identifiable, Hashable, Codable {
  var id: UUID
  var name: String
  var note: String?
  var contactIdentifier: String?
  /// A small JPEG of the person, if one has been chosen.
  var photoData: Data? = nil
}
