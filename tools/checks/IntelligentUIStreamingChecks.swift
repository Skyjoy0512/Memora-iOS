import Foundation

@main
struct IntelligentUIStreamingChecks {
  @MainActor static func main() throws {
    let component = #"{"id":"one","kind":"Disclosure","title":"補足","items":[{"id":"a","title":"日本語👨‍👩‍👧‍👦","detail":"引用\"と\\と[括弧]{ }"}]}"#
    let second = component.replacingOccurrences(of: #""id":"one""#, with: #""id":"two""#)
    let firstPrefix = #"{"version":1,"components":["# + component
    let json = firstPrefix + "," + second + "]}"
    var stream = NativeAIComponentStream()
    var prefix = ""
    var firstVisibleAt: Int?
    for char in json {
      prefix.append(char)
      let result = stream.update(prefix)
      if firstVisibleAt == nil, result != nil { firstVisibleAt = prefix.utf8.count }
      if prefix.utf8.count < firstPrefix.utf8.count { precondition(result == nil, "Partial component displayed") }
      if prefix.hasPrefix(firstPrefix) && !prefix.hasSuffix("]}") && !prefix.hasSuffix(second) {
        precondition(result?.components.first?.id == "one", "Completed prefix disappeared")
      }
    }
    precondition(firstVisibleAt == firstPrefix.utf8.count && firstVisibleAt! < json.utf8.count)
    precondition(stream.update(json)?.components.map(\.id) == ["one", "two"])
    precondition(stream.processedBytes == json.utf8.count && stream.validations == 3)
    precondition(stream.update(json)?.components.count == 2 && stream.validations == 3)
    let replaced = #"{"version":1,"components":["# + second + "]}"
    precondition(stream.update(replaced)?.components.first?.id == "two")
    for input in [firstPrefix + "," + component + "]}", firstPrefix + ",0]}", firstPrefix + ",{}]}",
      json + "not json", json.replacingOccurrences(of: "Disclosure", with: "WebView"),
      json.replacingOccurrences(of: #""version":1"#, with: #""version":2"#),
      #"{"version":1,"components":[]}"#, String(repeating: "x", count: 32 * 1024 + 1)] {
      var decoder = NativeAIComponentStream()
      precondition(decoder.update(input) == nil, "Invalid envelope rendered")
    }
    let taskID = "00000000-0000-0000-0000-000000000001"
    let progress = #"{"version":1,"components":[{"id":"p","kind":"TaskProgress","items":[{"id":"a","referenceID":""# + taskID + #""}]}]}"#
    precondition(NativeAIInterface.decode(progress) != nil)
    precondition(NativeAIInterface.decode(progress.replacingOccurrences(of: "TaskProgress", with: "MailDraftCard")) != nil)
    precondition(NativeAIInterface.decode(progress.replacingOccurrences(of: #""referenceID""#, with: #""action":"completeTask","referenceID""#)) == nil)
    precondition(NativeAIInterface.decode(progress.replacingOccurrences(of: #""referenceID""#, with: #""value":100,"referenceID""#)) == nil)
    let duplicate = progress.replacingOccurrences(of: #""referenceID":""# + taskID + #""}"#,
      with: #""referenceID":""# + taskID + #""},{"id":"b","referenceID":""# + taskID + #""}"#)
    precondition(NativeAIInterface.decode(duplicate) == nil)

    let answer = "通常の本文\n```memora-ui\n" + json + "\n```"
    let cache = NativeAIResponseCache()
    let streamed = cache.response(for: "通常の本文\n```memora-ui\n" + firstPrefix, isStreaming: true)
    precondition(streamed.markdown == "通常の本文" && streamed.interface?.components.count == 1)
    precondition(cache.response(for: answer, isStreaming: true).interface?.components.count == 2)
    precondition(cache.response(for: answer, isStreaming: false).interface?.components.count == 2)
    precondition(cache.response(for: "別の通常回答", isStreaming: true).interface == nil)
    precondition(cache.response(for: "別の通常回答", isStreaming: false).markdown == "別の通常回答")
    precondition(cache.response(for: answer + "trailing", isStreaming: false).interface == nil)
    // Old kind names and v1 histories stay accepted without any new fields.
    let old = #"{"version":1,"components":[{"id":"t","kind":"Timeline","items":[{"id":"i","title":"過去の履歴"}]}]}"#
    precondition(NativeAIInterface.decode(old) != nil)
    print("IntelligentUIStreamingChecks: passed (complete component prefix, Japanese/escapes/nesting, stable IDs, append-only scan, replacement/final cache, unknown/duplicate/oversize rejection, live-ID progress/mail schemas, no arbitrary actions, old v1)")

    let completed = AgentStep(icon: .magnifyingglass, title: "検索", state: .done)
    let failed = AgentStep(icon: .docText, title: "取得", state: .failed)
    let declined = AgentStep(icon: .envelope, title: "下書き", state: .declined)
    precondition(AgentActivitySummary(steps: [], isRunning: false, isWaiting: false).total == 0)
    precondition(AgentActivitySummary(steps: [completed, failed], isRunning: false, isWaiting: false).label.contains("失敗1件"))
    precondition(AgentActivitySummary(steps: [completed, declined], isRunning: false, isWaiting: false).label.contains("実行せず1件"))
    precondition(AgentActivitySummary(steps: [completed], isRunning: true, isWaiting: true).label.contains("確認待ち"))
    precondition(!AgentActivitySummary(steps: [completed], isRunning: false, isWaiting: true).isWaiting)
    print("AgentActivitySummaryChecks: passed (actual event counts/state only, failure/decline/waiting, no reasoning input)")

    // Same finalized source receives view invalidations unrelated to its JSON.
    // Timings measure host parsing only, not iPhone rendering, FPS or memory.
    let clock = ContinuousClock()
    var sink = 0
    let uncached = clock.measure { for _ in 0..<1000 { sink += NativeAIInterface.response(answer).interface?.components.count ?? 0 } }
    let stable = NativeAIResponseCache()
    let cached = clock.measure { for _ in 0..<1000 { sink += stable.response(for: answer, isStreaming: false).interface?.components.count ?? 0 } }
    precondition(sink == 4000)
    print("Host UI parse benchmark, 1000 identical settled renders: uncached=\(uncached), cached=\(cached); 2 components, \(answer.utf8.count) UTF8 bytes; not device/FPS evidence")
  }
}
