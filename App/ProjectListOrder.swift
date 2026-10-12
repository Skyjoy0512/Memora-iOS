import Foundation

enum ProjectListOrder: String, CaseIterable, Identifiable {
  case name
  case latestRecord

  var id: Self { self }
  var title: String { self == .name ? "名前順" : "最新記録順" }

  func ordered(_ projects: [MemoraSpace], latestDates: [UUID: Date]) -> [MemoraSpace] {
    projects.sorted { first, second in
      if self == .latestRecord {
        let firstDate = latestDates[first.id] ?? .distantPast
        let secondDate = latestDates[second.id] ?? .distantPast
        if firstDate != secondDate { return firstDate > secondDate }
      }
      let comparison = first.name.localizedStandardCompare(second.name)
      return comparison == .orderedSame ? first.id.uuidString < second.id.uuidString : comparison == .orderedAscending
    }
  }
}
