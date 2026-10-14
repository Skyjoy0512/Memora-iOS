import Foundation

@main
struct NativeAIInterfaceChecks {
  static func main() throws {
    let json = #"{"version":1,"components":[{"id":"table","kind":"ComparisonTable","columns":["対象","件数"],"items":[{"id":"a","cells":["前月","3"]}]},{"id":"chart","kind":"Chart","items":[{"id":"a","title":"記録数","value":3}]},{"id":"timeline","kind":"Timeline","items":[{"id":"a","title":"1日目","detail":"資料から検討"}]}]}"#
    precondition(NativeAIInterface.decode(json)?.components.count == 3)
    let answer = "Markdownの回答\n\n```memora-ui\n" + json + "\n```"
    let parsed = NativeAIInterface.response(answer)
    precondition(parsed.markdown == "Markdownの回答" && parsed.interface != nil)
    precondition(NativeAIInterface.response(answer, isStreaming: true).interface == nil)
    precondition(NativeAIInterface.response("```memora-ui\n{", isStreaming: true).markdown.isEmpty)
    precondition(!NativeAIInterface.response("```memora-ui\n{").markdown.isEmpty)
    precondition(NativeAIInterface.response("通常の回答").markdown == "通常の回答")
    precondition(NativeAIInterface.response("回答\n```memora-ui\n{" ).markdown == "回答")
    for unsafe in [
      json.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
      json.replacingOccurrences(of: "\"Chart\"", with: "\"WebView\""),
      json.replacingOccurrences(of: "\"value\":3", with: "\"value\":-1"),
      json.replacingOccurrences(of: "\"value\":3", with: "\"value\":true"),
      json.replacingOccurrences(of: "\"value\":3", with: "\"value\":3,\"url\":\"https://example.com\""),
      json.replacingOccurrences(of: "[\"前月\",\"3\"]", with: "[\"前月\"]"),
      json.replacingOccurrences(of: "\"id\":\"chart\"", with: "\"id\":\"table\""),
      #"{"version":1,"components":[{"id":"a","kind":"TaskList","items":[{"id":"a","referenceID":"not-a-uuid"}]}]}"#,
      #"{"version":1,"components":[{"id":"a","kind":"TaskList","items":[{"id":"a","referenceID":"00000000-0000-0000-0000-000000000001","action":"sendEmail"}]}]}"#,
      String(repeating: "x", count: 32 * 1024 + 1)
    ] { precondition(NativeAIInterface.decode(unsafe) == nil) }
    let bad = NativeAIInterface.response("読める回答\n```memora-ui\n{\"kind\":\"WebView\"}\n```")
    precondition(bad.markdown == "読める回答" && bad.interface == nil)
    let task = #"{"version":1,"components":[{"id":"a","kind":"TaskList","items":[{"id":"a","referenceID":"00000000-0000-0000-0000-000000000001","action":"completeTask"}]}]}"#
    precondition(NativeAIInterface.decode(task) != nil)
    print("NativeAIInterfaceChecks: passed (typed components, Markdown fallback, incomplete input, unknown components/keys/actions, malformed IDs, bounds, table shape, duplicate identity)")
  }
}
