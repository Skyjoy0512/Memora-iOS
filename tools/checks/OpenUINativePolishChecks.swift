import Foundation

/// Host checks for the OpenUI-derived native polish of the structured answer
/// interface. Pure presentation logic and the display schema only; no SwiftUI,
/// no model, no network, no real records.
@main
struct OpenUINativePolishChecks {
  static func main() throws {
    tableLayout()
    taskProgressSummary()
    sourceListRows()
    schema()
    streaming()
    print("OpenUINativePolishChecks: passed (comparison-table widths incl. large text/long cells/invalid viewports, task progress counts from tasks only, source rows resolved from stored sources with availability, ComparisonTable evidence reference accepted and still bounded, live component streaming)")
  }

  // MARK: ComparisonTable widths

  static func tableLayout() {
    let standard = AIInterfaceTableLayout.widths(header: ["項目", "説明"], rows: [], availableWidth: 400)
    precondition(standard == [192, 192], "A short table should fill the viewport")
    let weighted = AIInterfaceTableLayout.widths(header: ["項目", "説明"],
      rows: [["費用", "範囲と追加費用を確認する"]], availableWidth: 400)
    precondition(weighted[1] > weighted[0], "Japanese detail needs more room than its label")
    let largeText = AIInterfaceTableLayout.widths(header: ["A", "B", "C", "D"], rows: [],
      availableWidth: 320, minimumWidth: 240)
    precondition(largeText.allSatisfy { $0 >= 240 } && largeText.reduce(0, +) > 320,
      "Accessibility text must scroll rather than shrink")
    for viewport: CGFloat in [0, 1, -100, .nan, .infinity] {
      let widths = AIInterfaceTableLayout.widths(header: ["項目", "内容", "期限"],
        rows: [["短い"], [], ["A", "B", "C", "extra ignored"]], availableWidth: viewport)
      precondition(widths.count == 3 && widths.allSatisfy { $0.isFinite && $0 >= 96 })
    }
    let extreme = AIInterfaceTableLayout.widths(header: ["項目", "内容"],
      rows: [["A", String(repeating: "長文", count: 10_000)]], availableWidth: 1024)
    precondition(extreme[0] >= 96 && extreme[1] < 1024, "One huge cell must not unbound the table")
    precondition(AIInterfaceTableLayout.widths(header: [], rows: [["孤立"]], availableWidth: 400).isEmpty)
    let many = AIInterfaceTableLayout.widths(header: Array(repeating: "列", count: 20),
      rows: Array(repeating: ["値"], count: 1000), availableWidth: 400)
    precondition(many.count == 20 && many.allSatisfy { $0 == 96 })
  }

  // MARK: TaskProgress summary

  static func taskProgressSummary() {
    let empty = AIInterfaceTaskProgressSummary(tasks: [])
    precondition(empty.total == 0 && empty.completed == 0 && empty.fraction == 0 && !empty.isComplete)
    precondition(empty.accessibilityValue == "0件中0件が完了")
    let tasks = [
      MemoraTask(id: UUID(), title: "架空の確認", isCompleted: true),
      MemoraTask(id: UUID(), title: "架空の見積もり", isCompleted: false),
      MemoraTask(id: UUID(), title: "架空の連絡", isCompleted: false)
    ]
    let partial = AIInterfaceTaskProgressSummary(tasks: tasks)
    precondition(partial.total == 3 && partial.completed == 1 && partial.remaining == 2)
    precondition(abs(partial.fraction - 1.0 / 3.0) < 0.0001 && !partial.isComplete)
    precondition(partial.accessibilityValue == "3件中1件が完了")
    let done = AIInterfaceTaskProgressSummary(tasks: tasks.map { var task = $0; task.isCompleted = true; return task })
    precondition(done.completed == 3 && done.remaining == 0 && done.fraction == 1 && done.isComplete)
  }

  // MARK: SourceList rows

  static func sourceListRows() {
    let available = UUID()
    let revoked = UUID()
    let missing = UUID()
    let sources: [UUID: AIChatSource] = [
      available: AIChatSource(meetingID: available, title: "架空の定例会議",
        excerpts: [.init(text: "架空の引用", start: 12), .init(text: "別の引用", start: 40)]),
      revoked: AIChatSource(meetingID: revoked, title: "架空の失効した会議")
    ]
    let items = [
      NativeAIInterface.Item(id: "a", detail: "第3四半期の見積もり", referenceID: available),
      NativeAIInterface.Item(id: "b", referenceID: revoked),
      NativeAIInterface.Item(id: "c", referenceID: missing)
    ]
    let rows = AIInterfaceSourceListModel.rows(items: items, sources: sources,
      isAvailable: { $0 == available })
    precondition(rows.count == 2, "A source not in the message grounds is dropped")
    precondition(rows[0].title == "架空の定例会議" && rows[0].supplement == "第3四半期の見積もり"
      && rows[0].excerptCount == 2 && rows[0].isAvailable)
    precondition(rows[1].title == "架空の失効した会議" && rows[1].isAvailable == false
      && rows[1].excerptCount == 0 && rows[1].supplement == nil)
    // A record renamed to blank cannot become a row.
    let blank = AIInterfaceSourceListModel.rows(
      items: [NativeAIInterface.Item(id: "x", referenceID: available)],
      sources: [available: AIChatSource(meetingID: available, title: "  ")],
      isAvailable: { _ in true })
    precondition(blank.isEmpty)
    let none = AIInterfaceSourceListModel.rows(items: items, sources: [:], isAvailable: { _ in true })
    precondition(none.isEmpty)
  }

  // MARK: Display schema

  static func schema() {
    let id = "00000000-0000-0000-0000-000000000001"
    let evidence = #"{"version":1,"components":[{"id":"t","kind":"ComparisonTable","columns":["候補","費用"],"items":[{"id":"a","cells":["A案","100"],"referenceID":""# + id + #""}]}]}"#
    precondition(NativeAIInterface.decode(evidence) != nil, "A comparison row may cite a real record")
    let plain = #"{"version":1,"components":[{"id":"t","kind":"ComparisonTable","columns":["候補","費用"],"items":[{"id":"a","cells":["A案","100"]}]}]}"#
    precondition(NativeAIInterface.decode(plain) != nil)
    for unsafe in [
      evidence.replacingOccurrences(of: "[\"A案\",\"100\"]", with: "[\"A案\"]"),
      evidence.replacingOccurrences(of: "\"cells\"", with: "\"action\":\"completeTask\",\"cells\""),
      evidence.replacingOccurrences(of: "\"cells\"", with: "\"value\":3,\"cells\""),
      evidence.replacingOccurrences(of: #""referenceID":""# + id + #"""#, with: #""referenceID":"not-a-uuid""#)
    ] {
      precondition(NativeAIInterface.decode(unsafe) == nil, "Comparison row must stay bounded")
    }
    let source = #"{"version":1,"components":[{"id":"s","kind":"SourceList","items":[{"id":"a","referenceID":""# + id + #""}]}]}"#
    precondition(NativeAIInterface.decode(source) != nil)
    let duplicate = #"{"version":1,"components":[{"id":"p","kind":"TaskProgress","items":[{"id":"a","referenceID":""# + id + #""},{"id":"b","referenceID":""# + id + #""}]}]}"#
    precondition(NativeAIInterface.decode(duplicate) == nil)
  }

  // MARK: Streaming

  static func streaming() {
    let id = "00000000-0000-0000-0000-000000000001"
    let json = #"{"version":1,"components":[{"id":"t","kind":"ComparisonTable","columns":["候補","費用"],"items":[{"id":"a","cells":["A案","100"],"referenceID":""# + id + #""}]}]}"#
    var stream = NativeAIComponentStream()
    var prefix = ""
    var visibleAt: Int?
    for character in json {
      prefix.append(character)
      if visibleAt == nil, stream.update(prefix) != nil { visibleAt = prefix.utf8.count }
    }
    precondition(visibleAt != nil && visibleAt! < json.utf8.count,
      "The table shows once its component closes, not before the envelope ends")
    precondition(stream.update(json)?.components.first?.items.first?.referenceID != nil)
  }
}
