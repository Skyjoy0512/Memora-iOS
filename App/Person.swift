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
  var privacy = RecordPrivacy(classification: .personal)

  var effectivePrivacy: RecordPrivacy {
    var result = privacy
    result.protect(.personal)
    return result
  }
}

extension Person {
  private enum CodingKeys: String, CodingKey {
    case id, name, note, contactIdentifier, photoData, privacy
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    note = try container.decodeIfPresent(String.self, forKey: .note)
    contactIdentifier = try container.decodeIfPresent(String.self, forKey: .contactIdentifier)
    photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
    privacy = try container.decodeIfPresent(RecordPrivacy.self, forKey: .privacy) ?? RecordPrivacy(classification: .personal)
  }
}
