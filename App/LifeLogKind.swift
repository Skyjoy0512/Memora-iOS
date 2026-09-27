import Foundation

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

  var symbol: MemoraIcon {
    switch self {
    case .memo: .noteText
    case .photo: .photo
    case .event: .calendar
    case .location: .location
    }
  }
}
