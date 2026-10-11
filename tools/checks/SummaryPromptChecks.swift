import Foundation

@main
struct SummaryPromptChecks {
  static func main() {
    for id in ["work.customer-chart", "work.care", "work.daily", "work.journal"] {
      guard let template = SummaryTemplateCatalog.template(id: id) else { preconditionFailure(id) }
      let input = MeetingSummaryInput(title: "記録", date: .now, duration: 60,
        participantNames: [], transcript: [], template: .market(template))
      let format = SummaryPrompt.format(for: input.template, input: input)
      precondition(!format.contains("\n## 未決事項"))
      var previous = format.startIndex
      for section in template.sections {
        guard let range = format.range(of: "## \(section)", range: previous..<format.endIndex) else {
          preconditionFailure("section order: \(id)")
        }
        previous = range.upperBound
      }
      let notes = SummaryPrompt.partNotes(for: input, part: 1, of: 3, range: "00:00〜10:00", transcript: "原文")
      precondition(notes.contains(template.focus))
      precondition(template.sections.allSatisfy { notes.contains($0) })
      precondition(notes.contains("数量") && notes.contains("原文にない事実を追加しない"))
    }
    let minutes = MeetingSummaryInput(title: "会議", date: .now, duration: 60,
      participantNames: [], transcript: [], template: .builtIn(.meetingMinutes))
    precondition(SummaryPrompt.format(for: minutes.template, input: minutes).contains("## 未決事項"))
    precondition(SummaryPrompt.dataContract.contains("\"templateID\""))
    precondition(!SummaryPrompt.system.contains("Markdownだけ"))
    var custom = SummaryTemplateCatalog.market[0]
    custom.isCustom = true
    custom.sections = ["私の見出し"]
    custom.prompt = ""
    precondition(!SummaryPrompt.format(for: .market(custom), input: minutes).contains("## 未決事項"))
    print("SummaryPromptChecks: passed (headings, order, intermediate focus, contract)")
  }
}
