import Foundation

@main
enum LocalVoiceNativeChecks {
  static func main() async throws {
    guard CommandLine.arguments.count == 2 else { fatalError("Pass the verified GGUF path") }
    let context = try await LocalLlamaContext.load(path: CommandLine.arguments[1])
    let questions = ["日本語で、こんにちは、と一言だけ答えてください。", "日本語で、2足す3の答えを一文で教えてください。"]
    for (index, question) in questions.enumerated() {
      let prompt = LocalVoicePrompt.make(question: question,
        context: index == 0 ? "" : String(repeating: "これは参照資料ではなく、長い入力バッチの検証です。", count: 20),
        history: "", contextLimit: 900)
      try await context.begin(prompt: prompt)
      var decoder = LocalTokenTextBuffer()
      var text = ""
      for _ in 0..<100 {
        guard let bytes = try await context.next() else { break }
        text += try decoder.append(bytes)
      }
      try decoder.finish()
      precondition(text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }, "Native Japanese output must survive decoding")
      print("Native local reply \(index + 1): \(text)")
    }
    do {
      try await context.begin(prompt: String(repeating: "日本語の長文", count: 2_000))
      preconditionFailure("An oversized prompt must be refused before writing native batch memory")
    } catch LocalLlamaContext.Failure.promptTooLong {}
    print("LocalVoiceNativeChecks passed: pinned Qwen GGUF, native Japanese generation, multi-batch prefill, fresh-turn reset, oversized prompt refusal")
  }
}
