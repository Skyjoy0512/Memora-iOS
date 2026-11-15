import Foundation

@main
struct LiveConversationChecks {
  static func main() {
    let examples = [
      "日本語の最初の文。次の文！最後の質問？",
      "Hello! Next sentence. More words? Last answer.",
      "価格は3.14です。担当は佐藤さん。",
      String(repeating: "日本語の長い文", count: 100) + "。後半です。",
      String(repeating: "👨‍👩‍👧‍👦", count: 440) + "。"
    ]
    for source in examples {
      let characters = Array(source)
      for strideLength in [1, 2, 5, 17, 200, 9999] {
        var buffer = LiveSentenceBuffer()
        var sentences: [String] = []
        for start in stride(from: 0, to: characters.count, by: strideLength) {
          sentences += buffer.append(String(characters[start..<min(characters.count, start + strideLength)]))
        }
        sentences += buffer.flush()
        precondition(sentences.allSatisfy { !$0.isEmpty && $0.count <= 200 }, "Speech must stay bounded, including Japanese without spaces")
        precondition(normalize(sentences.joined()) == normalize(source), "No skipped character at a boundary, including grapheme clusters")
        precondition(buffer.flush().isEmpty, "Repeated completion cannot repeat speech")
      }
    }
    var buffer = LiveSentenceBuffer()
    precondition(buffer.append("最初の文。次").first == "最初の文。")
    precondition(buffer.append("の文。").first == "次の文。")
    _ = buffer.append("割り込みで破棄する未完成文")
    buffer.reset()
    precondition(buffer.flush().isEmpty)

    var authority = LiveTurnAuthority()
    authority.attachResponse(UUID())
    precondition(authority.responseID == nil, "An inactive session cannot take a reply")
    let firstSession = authority.begin()
    let firstReply = UUID()
    authority.attachResponse(firstReply)
    let firstRevision = authority.revision
    precondition(authority.allows(session: firstSession, revision: firstRevision))
    precondition(authority.interrupt() == firstReply)
    precondition(!authority.allows(session: firstSession, revision: firstRevision), "Old audio and LLM chunks must be rejected after barge-in")
    let replacement = UUID()
    authority.attachResponse(replacement)
    let secondRevision = authority.revision
    precondition(!authority.allows(session: firstSession, revision: firstRevision))
    precondition(authority.responseID == replacement, "Stale work cannot own the replacement reply")
    authority.stop()
    precondition(!authority.allows(session: firstSession, revision: secondRevision))
    let nextSession = authority.begin()
    precondition(nextSession != firstSession && authority.responseID == nil)
    precondition(!authority.allows(session: firstSession, revision: authority.revision), "Workspace/foreground restarts must invalidate old callbacks")
    print("LiveConversationChecks: Japanese/English token fragmentation, bounded long sentences, grapheme preservation, no duplicate flush, interruption and session replacement passed")
  }

  static func normalize(_ value: String) -> String { String(value.filter { !$0.isWhitespace }) }
}
