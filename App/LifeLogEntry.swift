import Foundation

struct LifeLogEntry: Identifiable, Hashable, Codable {
  var id: UUID
  var createdAt: Date
  var title: String
  var summary: String
  var source: LifeLogSource
  var meetingID: UUID?
  var kind = LifeLogKind.memo
  var photoData: Data?
  var eventDate: Date?
  var locationName: String?
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
