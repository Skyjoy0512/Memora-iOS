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
    checkInputHealth()
    print("LiveConversationChecks: text fragmentation, bounded sentences, stale callbacks, missing microphone, stalled recognition and quiet/response intervals passed")
  }

  static func checkInputHealth() {
    var missing = LiveInputHealth()
    precondition(missing.check(elapsed: 2, frames: 0, voicedSeconds: 0, expectsRecognition: true) == nil)
    precondition(missing.check(elapsed: 3, frames: 0, voicedSeconds: 0, expectsRecognition: true) == .noMicrophoneBuffers)
    var disconnected = LiveInputHealth()
    precondition(disconnected.check(elapsed: 1, frames: 48000, voicedSeconds: 0, expectsRecognition: true) == nil)
    precondition(disconnected.check(elapsed: 4, frames: 48000, voicedSeconds: 0, expectsRecognition: true) == .noMicrophoneBuffers)
    var silent = LiveInputHealth()
    for second in 1...120 {
      precondition(silent.check(elapsed: Double(second), frames: second * 48000,
        voicedSeconds: 0, expectsRecognition: true) == nil, "Silence must not report a failed recognizer")
    }
    var stalled = LiveInputHealth()
    for second in 1...15 {
      precondition(stalled.check(elapsed: Double(second), frames: second * 48000,
        voicedSeconds: Double(second), expectsRecognition: true) == nil)
    }
    precondition(stalled.check(elapsed: 16, frames: 16 * 48000, voicedSeconds: 16,
      expectsRecognition: true) == .recognitionStalled)
    var recognised = LiveInputHealth()
    _ = recognised.check(elapsed: 1, frames: 48000, voicedSeconds: 1, expectsRecognition: true)
    recognised.receivedResult(at: 1)
    for second in 2...60 {
      precondition(recognised.check(elapsed: Double(second), frames: second * 48000,
        voicedSeconds: 1, expectsRecognition: true) == nil, "Quiet after recognised speech is normal")
    }
    var betweenPolls = LiveInputHealth()
    betweenPolls.receivedResult(at: 0.1)
    for second in 1...60 {
      precondition(betweenPolls.check(elapsed: Double(second), frames: second * 48000,
        voicedSeconds: 1, expectsRecognition: true) == nil, "A result preceding the meter poll must cover that audio")
    }
    var reply = LiveInputHealth()
    for second in 1...60 {
      precondition(reply.check(elapsed: Double(second), frames: second * 48000,
        voicedSeconds: Double(second), expectsRecognition: false) == nil, "AI thinking/playback is not a recognizer stall")
    }
    precondition(reply.check(elapsed: 61, frames: 61 * 48000, voicedSeconds: 60,
      expectsRecognition: true) == nil, "Reply audio must not become evidence of a microphone stall")
  }

  static func normalize(_ value: String) -> String { String(value.filter { !$0.isWhitespace }) }
}
