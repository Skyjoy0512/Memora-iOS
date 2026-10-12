import Foundation

@main
struct ProjectListOrderChecks {
  static func main() {
    let first = MemoraSpace(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Project 2", symbol: "folder")
    let second = MemoraSpace(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Project 10", symbol: "folder")
    let unrecorded = MemoraSpace(id: UUID(), name: "Project 1", symbol: "folder")
    precondition(ProjectListOrder.name.ordered([], latestDates: [:]).isEmpty)
    precondition(ProjectListOrder.name.ordered([first], latestDates: [:]) == [first])
    precondition(ProjectListOrder.name.ordered([second, first], latestDates: [:]) == [first, second])
    let dates = [first.id: Date(timeIntervalSince1970: 1), second.id: Date(timeIntervalSince1970: 2)]
    precondition(ProjectListOrder.latestRecord.ordered([unrecorded, first, second], latestDates: dates) == [second, first, unrecorded])
    var sameName = second
    sameName.name = first.name
    precondition(ProjectListOrder.name.ordered([sameName, first], latestDates: [:]) == [first, sameName])
    let many = (1...100).reversed().map { MemoraSpace(id: UUID(), name: "Project \($0)", symbol: "folder") }
    let ordered = ProjectListOrder.name.ordered(many, latestDates: [:])
    precondition(ordered.count == 100 && Set(ordered.map(\.id)) == Set(many.map(\.id)))
    precondition(ordered.first?.name == "Project 1" && ordered.last?.name == "Project 100")
    print("ProjectListOrderChecks: passed (0/1/100 items, natural names, latest record, missing dates, stable ties)")
  }
}
