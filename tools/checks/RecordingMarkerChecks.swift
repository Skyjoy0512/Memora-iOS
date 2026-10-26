import Foundation

@main
struct RecordingMarkerChecks {
  static func main() throws {
    let first = RecordingMarker(timestamp: 0)
    let second = RecordingMarker(timestamp: 30, title: "決定した場面")
    let added = RecordingMarker.adding(at: 31, to: [first, second])
    precondition(added?.count == 3 && added?.last?.timestamp == 31)
    precondition(RecordingMarker.adding(at: 30.5, to: [second]) == nil)
    precondition(RecordingMarker.adding(at: .nan, to: []) == nil)
    precondition(RecordingMarker.adding(at: .infinity, to: []) == nil)
    precondition(RecordingMarker.adding(at: -1, to: []) == nil)
    precondition(RecordingMarker.validated([second, first, second], duration: 60) == [first, second])
    precondition(RecordingMarker.validated([second, first], duration: 10) == [first])
    precondition(RecordingMarker.validated([first], duration: .nan).isEmpty)
    precondition(RecordingMarker.validated([second, first, second], duration: nil) == [first, second])
    precondition(RecordingMarker.validated([RecordingMarker(timestamp: .infinity),
      RecordingMarker(timestamp: -1), RecordingMarker(timestamp: Double(Int.max))], duration: nil).isEmpty)
    precondition(RecordingMarker(timestamp: 1, title: " \n").displayTitle == "重要な場面")
    let data = try JSONEncoder().encode([first, second])
    let restored = try JSONDecoder().decode([RecordingMarker].self, from: data)
    precondition(restored == [first, second])
    print("Recording marker checks passed")
  }
}
