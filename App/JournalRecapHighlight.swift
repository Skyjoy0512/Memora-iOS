import Foundation

struct JournalRecapHighlight: Identifiable {
  var id: UUID
  var date: Date
  var kind: Kind
  var title: String
  var summary: String

  var label: String { "\(category)：\(title)" }

  var category: String { kind.label }

  var icon: MemoraIcon {
    switch kind {
    case .record: .waveform
    case .completedTask: .checkmark
    case .memo: .noteText
    case .photo: .photo
    case .location: .location
    case .event: .calendar
    }
  }

  enum Kind: CaseIterable, Hashable {
    case record, completedTask, memo, photo, location, event

    var label: String {
      switch self {
      case .record: "会議・録音"
      case .completedTask: "完了"
      case .memo: "メモ"
      case .photo: "写真"
      case .location: "場所"
      case .event: "イベント"
      }
    }

    init(_ kind: LifeLogKind) {
      switch kind {
      case .memo: self = .memo
      case .photo: self = .photo
      case .location: self = .location
      case .event: self = .event
      }
    }
  }
}
