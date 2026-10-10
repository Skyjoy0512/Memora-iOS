import Foundation

struct JournalRecapHighlight: Identifiable {
  var id: UUID
  var date: Date
  var category: String
  var icon: MemoraIcon
  var title: String
  var summary: String

  var label: String { "\(category)：\(title)" }
}
