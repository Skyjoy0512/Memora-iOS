import Foundation

struct LifeLogEntry: Identifiable, Hashable, Codable {
  var id: UUID
  var createdAt: Date
  var title: String
  var summary: String
  var source: LifeLogSource
  var meetingID: UUID?
  var kind = LifeLogKind.memo
  /// File name of the attached photo, inside the media folder.
  var photoFileName: String?
  var eventDate: Date?
  var locationName: String?
}

extension LifeLogEntry {
  private enum CodingKeys: String, CodingKey {
    case id
    case createdAt
    case title
    case summary
    case source
    case meetingID
    case kind
    case photoFileName
    /// Legacy: the photo used to be stored inline in the entry.
    case photoData
    case eventDate
    case locationName
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    title = try container.decode(String.self, forKey: .title)
    summary = try container.decode(String.self, forKey: .summary)
    source = try container.decode(LifeLogSource.self, forKey: .source)
    meetingID = try container.decodeIfPresent(UUID.self, forKey: .meetingID)
    kind = try container.decodeIfPresent(LifeLogKind.self, forKey: .kind) ?? .memo
    eventDate = try container.decodeIfPresent(Date.self, forKey: .eventDate)
    locationName = try container.decodeIfPresent(String.self, forKey: .locationName)

    if let name = try container.decodeIfPresent(String.self, forKey: .photoFileName) {
      photoFileName = name
    } else if let legacy = try container.decodeIfPresent(Data.self, forKey: .photoData) {
      // Written out the first time the entry is read.
      photoFileName = MediaFiles.writePhoto(legacy)
    } else {
      photoFileName = nil
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(title, forKey: .title)
    try container.encode(summary, forKey: .summary)
    try container.encode(source, forKey: .source)
    try container.encodeIfPresent(meetingID, forKey: .meetingID)
    try container.encode(kind, forKey: .kind)
    try container.encodeIfPresent(photoFileName, forKey: .photoFileName)
    try container.encodeIfPresent(eventDate, forKey: .eventDate)
    try container.encodeIfPresent(locationName, forKey: .locationName)
  }
}

enum LifeLogSource: String, Hashable, Codable {
  case iphone
  case omi
  case imported

  var label: String {
    switch self {
    case .iphone:
      "iPhone"
    case .omi:
      "Omi"
    case .imported:
      "取り込み"
    }
  }
}

enum LifeLogKind: String, CaseIterable, Identifiable, Codable {
  case memo
  case photo
  case event
  case location

  var id: Self { self }

  var label: String {
    switch self {
    case .memo: "メモ"
    case .photo: "写真"
    case .event: "イベント"
    case .location: "場所"
    }
  }

  var symbol: String {
    switch self {
    case .memo: "note.text"
    case .photo: "photo"
    case .event: "calendar"
    case .location: "location"
    }
  }
}
