import Foundation

@main
struct JSONRenderEnvelopeChecks {
  static func expect(_ condition: @autoclosure () -> Bool, line: Int = #line) {
    guard condition() else { FileHandle.standardError.write(Data("JSONRenderEnvelopeChecks failed at \(line)\n".utf8)); exit(1) }
  }

  @MainActor static func main() throws {
    let patch = #"{"op":"add","path":"/root","value":"main"}"#
    let answer = "本文【資料1】\n\n```spec\n" + patch + "\n```\n補足"
    let parsed = JSONRenderEnvelope.parse(answer)!
    expect(parsed.markdown == "本文【資料1】\n\n補足")
    expect(parsed.segments == [.init(format: "patch", text: patch, complete: true)])
    expect(NativeAIInterface.response(answer).markdown == parsed.markdown)
    for (fence, format) in JSONRenderEnvelope.fences {
      let complete = JSONRenderEnvelope.parse("本文\n```\(fence)\n{}\n```")!
      expect(complete.markdown == "本文" && complete.segments.first?.format == format && complete.segments.first?.complete == true)
      let partial = JSONRenderEnvelope.parse("本文\n```\(fence)\n{", isStreaming: true)!
      expect(partial.markdown == "本文" && partial.segments.first?.complete == false)
    }
    expect(JSONRenderEnvelope.parse("普通の本文") == nil)
    expect(JSONRenderEnvelope.parse("```swift\nlet example = 1\n```") == nil)
    expect(JSONRenderEnvelope.parse("```json\n" + patch + "\n```") == nil)
    expect(JSONRenderEnvelope.parse("本文\n```sp", isStreaming: true)?.markdown == "本文")
    let raw = JSONRenderEnvelope.parse("本文\n" + patch + "\n補足")!
    expect(raw.markdown == "本文\n補足" && raw.segments.first?.format == "patch")
    let multiple = JSONRenderEnvelope.parse(answer + "\n```yaml-edit\nstate:\n  x: true\n```")!
    expect(multiple.segments.count == 2 && multiple.segments.last?.format == "merge")
    expect(JSONRenderEnvelope.parse("```json-render\n" + String(repeating: "x", count: JSONRenderEnvelope.maximumBytes + 1) + "\n```")?.exceedsLimit == true)
    let fingerprint = JSONRenderSnapshot.fingerprint(answer)
    let spec = #"{"root":"main","elements":{"main":{"type":"Text","props":{"text":"本文"},"children":[]}}}"#
    let snapshot = JSONRenderSnapshot(fingerprint: fingerprint, specJSON: spec, stateJSON: #"{"name":"入力"}"#, text: "表示本文")
    expect(snapshot.isValid)
    let roundTrip = try JSONDecoder().decode(JSONRenderSnapshot.self, from: JSONEncoder().encode(snapshot))
    expect(roundTrip == snapshot)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("json-render-check-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LocalStore(fileURL: folder.appendingPathComponent("state.sqlite"))
    try store.prepare()
    try store.write("ui", data: JSONEncoder().encode(snapshot))
    guard case .data(let data) = store.readOutcome("ui") else { fatalError("Missing SQLite state") }
    let persisted = try JSONDecoder().decode(JSONRenderSnapshot.self, from: data)
    expect(persisted == snapshot)
    var invalid = snapshot
    invalid.stateJSON = String(repeating: "x", count: 65537)
    expect(!invalid.isValid)
    invalid = snapshot; invalid.specJSON = "{}"; expect(!invalid.isValid)
    invalid = snapshot; invalid.fingerprint = "forged"; expect(!invalid.isValid)
    print("JSONRenderEnvelopeChecks: passed (all wire formats, partial fences, mixed prose, ordinary code, bounds, fingerprint and real SQLite round trip)")
  }
}
