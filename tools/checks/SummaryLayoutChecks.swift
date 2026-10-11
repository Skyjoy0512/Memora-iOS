import Foundation

@main
struct SummaryLayoutChecks {
  static func main() {
    let context = MeetingSummaryInput(title: "記録", date: .now, duration: 60,
      participantNames: [], transcript: [], template: .builtIn(.meetingMinutes))
    let topics = [
      SummaryTopic(title: "先に話したこと", startTime: 0, endTime: 30, points: ["確認した事実"]),
      SummaryTopic(title: "決定したこと", startTime: 30, endTime: 60, points: ["合意した事実"], decisions: ["次回実施"])
    ]
    let important = SummaryMarkdownBuilder.build(template: context.template, input: context,
      headline: "記録", overview: "概要", topics: topics)
    precondition(important.range(of: "### 決定したこと")!.lowerBound < important.range(of: "### 先に話したこと")!.lowerBound)
    var chronological = context
    chronological.preferences.displayOrder = .chronological
    let ordered = SummaryMarkdownBuilder.build(template: context.template, input: chronological,
      headline: "記録", overview: "概要", topics: topics.reversed())
    precondition(ordered.range(of: "### 先に話したこと")!.lowerBound < ordered.range(of: "### 決定したこと")!.lowerBound)
    let timeline = SummaryMarkdownBuilder.build(template: .builtIn(.detailedMinutes), input: context,
      headline: "記録", overview: "概要", topics: topics.reversed())
    precondition(timeline.range(of: "先に話したこと")!.lowerBound < timeline.range(of: "決定したこと")!.lowerBound)
    precondition(SummaryLength.allCases.map(\.instruction).count == 3)
    print("SummaryLayoutChecks: passed (importance, chronological, explicit timeline)")
  }
}
