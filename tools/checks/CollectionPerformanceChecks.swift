import Foundation

@main
struct CollectionPerformanceChecks {
  static func main() {
    FileHandle.standardError.write(Data("CollectionPerformanceChecks locale=\(Locale.current.identifier)\n".utf8))
    for count in [0, 1, 100, 1_000] {
      let meetings = (0..<count).map { number in
        Meeting(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number + 1))!, title: "会議 \(number)",
          createdAt: Date(timeIntervalSince1970: 1_791_892_800).addingTimeInterval(-Double(number) * 86_400),
          decisions: [number.isMultiple(of: 3) ? "予算を決定" : ""], openQuestions: ["納期"],
          notes: "確認", summary: "概要", transcript: [TranscriptSegment(text: "箱根旅行の移動時間")])
      }
      let tasks = meetings.enumerated().flatMap { offset, meeting in
        [MemoraTask(title: "予算 \(offset)", meetingID: meeting.id), MemoraTask(title: "納期", meetingID: meeting.id)]
      } + [MemoraTask(title: "未所属", meetingID: nil)]
      for words in [[], ["予算"], ["移動", "納期"], ["一致しない"]] {
        precondition(MeetingRanking.rank(meetings: meetings, words: words, tasks: tasks) == LegacyRanking.rank(meetings: meetings, words: words, tasks: tasks))
      }
      for ordered in [meetings, Array(meetings.reversed()), meetings.sorted { $0.title > $1.title }] {
        let current = CurrentSections().build(ordered), legacy = LegacySections().build(ordered)
        if current != legacy {
          FileHandle.standardError.write(Data("Section equality failed count=\(count) current=\(current.map { ($0.id, $0.title) }) legacy=\(legacy.map { ($0.id, $0.title) })\n".utf8))
        }
        precondition(current == legacy)
        for section in current {
          let labels = ["today": "今日", "yesterday": "昨日", "week": "今週", "month": "今月"]
          if let label = labels[section.id] { precondition(section.title == label) }
          else {
            let date = SectionComparisonContext.calendar.dateComponents([.year, .month], from: section.meetings[0].createdAt)
            precondition(section.title == "\(date.year!)年\(date.month!)月", "Japanese UI heading changed")
          }
        }
      }
      if count >= 100 {
        benchmark("ranking", count: count) { MeetingRanking.rank(meetings: meetings, words: ["予算", "移動"], tasks: tasks).count }
        benchmark("sections", count: count) { CurrentSections().build(meetings).count }
      }
    }
    print("CollectionPerformanceChecks: passed (0/1/100/1000, ordering, no-match fallback, loose/multiple tasks)")
  }

  static func benchmark(_ name: String, count: Int, work: () -> Int) {
    var samples: [Double] = []
    for _ in 0..<21 {
      let start = ContinuousClock.now
      precondition(work() > 0)
      let duration = start.duration(to: .now).components
      samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
    }
    samples.sort()
    print(String(format: "%@,%d,median=%.3f,p95=%.3f,max=%.3f", name, count, samples[10], samples[19], samples[20]))
  }
}

// Ranking/grouping use only these fields; fixtures isolate the algorithms from
// UIKit, permissions and persistence. The runner compiles the actual ranking
// file and the date-section methods with explicit clock/calendar injection and
// the documented historical Japanese heading normalization.
struct Meeting: Equatable {
  var id: UUID
  var title: String
  var createdAt: Date
  var decisions: [String]
  var openQuestions: [String]
  var notes: String
  var summary: String
  var transcript: [TranscriptSegment]
}
struct TranscriptSegment: Equatable { var text: String }
struct MemoraTask { var title: String; var meetingID: UUID? }
struct FileDateSection: Equatable { var id: String; var title: String; var meetings: [Meeting] }

enum SectionComparisonContext {
  static let now = Date(timeIntervalSince1970: 1_792_972_800)
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
  static var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: now)! }
}
