import Foundation

@main
struct JSONRenderChecks {
  static func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed", line: Int = #line) {
    guard condition() else {
      FileHandle.standardError.write(Data("JSONRenderChecks line \(line): \(message)\n".utf8))
      exit(1)
    }
  }

  @MainActor static func main() throws {
    let root = #""answer":{"type":"Stack","props":{},"children":["metric","timeline"]}"#
    let metric = #""metric":{"type":"Metric","props":{"items":[{"id":"m","title":"差分（件）","value":-2,"detail":"引用\"と\\と日本語👨‍👩‍👧‍👦"}]},"children":[]}"#
    let timeline = #""timeline":{"type":"Timeline","props":{"title":"予定","items":[{"id":"t","title":"午後","detail":"振り返り"}]},"children":[]}"#
    let start = #"{"root":"answer","elements":{"#
    let metricPrefix = start + root + "," + metric
    let json = metricPrefix + "," + timeline + "}}"
    func answer(_ value: String) -> String { "本文\n```json-render\n" + value + "\n```" }
    func render(_ value: String) -> NativeAIInterface? { NativeAIInterface.response(answer(value)).interface }
    expect(render(json)?.components.map(\.id) == ["metric", "timeline"])
    let export = NativeAIInterface.exportMarkdown(answer(json))
    expect(export.contains("差分（件）") && export.contains("-2") && export.contains("振り返り") && !export.contains("json-render"))
    var stream = NativeAIComponentStream()
    var prefix = ""
    var visibleAt: Int?
    for character in json {
      prefix.append(character)
      let interface = stream.update(prefix, format: .jsonRender)
      if interface?.components.isEmpty == false, visibleAt == nil { visibleAt = prefix.utf8.count }
      if prefix.utf8.count < metricPrefix.utf8.count { expect(interface?.components.isEmpty != false) }
      if prefix.hasPrefix(metricPrefix) { expect(interface?.components.first?.id == "metric") }
    }
    expect(visibleAt == metricPrefix.utf8.count && stream.isComplete)
    expect(stream.processedBytes == json.utf8.count && stream.validations == 4)
    expect(stream.update(json, format: .jsonRender)?.components.count == 2 && stream.validations == 4)
    expect(stream.update(json + "garbage", format: .jsonRender) == nil && !stream.isComplete)
    let cache = NativeAIResponseCache()
    expect(cache.response(for: "本文\n```json-render\n" + metricPrefix, isStreaming: true).interface?.components.count == 1)
    expect(cache.response(for: answer(json), isStreaming: false).interface?.components.count == 2)
    expect(cache.response(for: "別の回答", isStreaming: false).interface == nil)
    for marker in ["```", "```j", "```json-", "```json-render"] {
      expect(NativeAIInterface.response("本文\n" + marker, isStreaming: true).markdown == "本文")
    }
    expect(NativeAIInterface.response(answer(metricPrefix)).interface == nil)
    expect(NativeAIInterface.response(answer(metricPrefix)).markdown == "本文")
    let linked = NativeAIInterface.mapAnswerMarkdown(answer(json)) { $0.replacingOccurrences(of: "本文", with: "[資料](memora-cite://1)") }
    expect(linked.contains("[資料](memora-cite://1)") && linked.hasSuffix("```"))
    expect(NativeAIInterface.response(linked).interface == render(json))
    let citedJSON = json.replacingOccurrences(of: "振り返り", with: "【資料1】")
    let cited = "【資料1】\n" + answer(citedJSON)
    let quotedLink = NativeAIInterface.mapAnswerMarkdown(cited) { $0.replacingOccurrences(of: "【資料1】", with: "[引用\"タイトル](memora-cite://1)") }
    expect(NativeAIInterface.response(quotedLink).interface == render(citedJSON))
    expect(quotedLink.contains("[引用\"タイトル](memora-cite://1)"))
    let legacy = #"""
    本文
    ```memora-ui
    {"components":[{"id":"old","kind":"Timeline","items":[{"id":"x","title":"旧形式"}]}],"version":1}
    ```
    """#
    expect(NativeAIInterface.response(legacy).interface?.components.first?.id == "old")
    for bad in [
      json.replacingOccurrences(of: "\"Metric\"", with: "\"WebView\""),
      json.replacingOccurrences(of: "\"value\":-2", with: "\"value\":true"),
      json.replacingOccurrences(of: "\"value\":-2", with: "\"value\":{\"$state\":\"/secret\"}"),
      json.replacingOccurrences(of: "\"value\":-2", with: "\"value\":1e100"),
      json.replacingOccurrences(of: "\"value\":-2", with: "\"value\":-2,\"url\":\"https://example.com\""),
      json.replacingOccurrences(of: "\"root\":\"answer\"", with: "\"root\":\"missing\""),
      json.replacingOccurrences(of: "[\"metric\",\"timeline\"]", with: "[\"metric\",\"missing\"]"),
      json.replacingOccurrences(of: "[\"metric\",\"timeline\"]", with: "[\"metric\",\"metric\"]"),
      json.replacingOccurrences(of: "[\"metric\",\"timeline\"]", with: "[\"answer\"]"),
      json.replacingOccurrences(of: "\"type\":\"Metric\"", with: "\"on\":{\"press\":\"sendEmail\"},\"type\":\"Metric\""),
      json.replacingOccurrences(of: "\"type\":\"Metric\"", with: "\"visible\":true,\"type\":\"Metric\""),
      json.replacingOccurrences(of: "\"root\":", with: "\"state\":{},\"root\":"),
      json.replacingOccurrences(of: "[\"metric\",\"timeline\"]", with: "[\"metric\"]"),
      json.replacingOccurrences(of: "," + timeline, with: "," + metric + "," + timeline),
      json + "trailing", String(repeating: " ", count: 32 * 1024) + json
    ] {
      expect(render(bad) == nil, "Unsafe spec rendered: " + bad.prefix(80))
      let result = NativeAIInterface.response(answer(bad), isStreaming: true)
      expect(result.interface == nil, "Unsafe stream rendered")
    }
    let row = #"{"root":"row","elements":{"row":{"type":"Row","props":{},"children":["metric","timeline"]},"# + metric + "," + timeline + "}}"
    expect(render(row)?.components.first?.components?.count == 2)
    expect(render(json.replacingOccurrences(of: "\"Metric\"", with: "\"Chart\"")) == nil)
    expect(render(json.replacingOccurrences(of: "\"value\":-2", with: "\"value\":null")) == nil)
    expect(NativeAIInterface.response(answer(metricPrefix), isStreaming: true).interface == nil)
    var rewritten = NativeAIComponentStream()
    _ = rewritten.update(metricPrefix, format: .jsonRender)
    expect(rewritten.update(row, format: .jsonRender)?.components.first?.id == "row")
    let nested = row.replacingOccurrences(of: "\"type\":\"Metric\"", with: "\"type\":\"Column\"")
    expect(render(nested) == nil)
    let reversed = start + timeline + "," + root + "," + metric + "}}"
    expect(render(reversed)?.components.map(\.id) == ["metric", "timeline"])
    let task = #"{"root":"task","elements":{"task":{"type":"TaskList","props":{"items":[{"id":"t","referenceID":"00000000-0000-0000-0000-000000000001","action":"completeTask"}]},"children":[]}}}"#
    expect(render(task)?.components.first?.items.first?.action == .completeTask)
    expect(render(task.replacingOccurrences(of: "completeTask", with: "sendEmail")) == nil)
    print("JSONRenderChecks: passed (catalog, progressive elements, stable IDs, exports, legacy, cache, limits, cycles, missing/shared/orphan/duplicate elements, unknown props/actions/state)")
  }
}
