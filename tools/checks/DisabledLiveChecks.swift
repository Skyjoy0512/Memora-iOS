import Foundation

// The real model-file probe is replaced with a counter; native access is fatal.
// This compiles the production LLM and downloader without a GGUF or network.
enum LocalVoiceModel {
  static var reads = 0
  static var isInstalled: Bool { reads += 1; return false }
  static var directory: URL { fatalError("Disabled Live accessed model directory") }
  static var fileURL: URL { fatalError("Disabled Live accessed model file") }
  static var receiptURL: URL { fatalError("Disabled Live accessed receipt") }
  static var downloadURL: URL { fatalError("Disabled Live accessed network URL") }
  static var byteCount: Int64 { fatalError("Disabled Live prepared download") }
  static var sha256: String { fatalError("Disabled Live verified model") }
}

actor LocalLlamaContext {
  enum Failure: Error { case promptTooLong }
  static func load(path: String) async throws -> LocalLlamaContext { fatalError("Disabled Live loaded native model") }
  func begin(prompt: String) throws { fatalError("Disabled Live began native generation") }
  func next() throws -> [UInt8]? { fatalError("Disabled Live decoded token") }
}

@main
struct DisabledLiveChecks {
  @MainActor static func main() async throws {
    precondition(!FeatureFlags.isLiveConversationEnabled)
    let llm = LocalVoiceLLM()
    for _ in 0..<100 {
      do {
        try await llm.prepare()
        preconditionFailure("Disabled prepare succeeded")
      } catch is LiveVoiceError {}
      let result = await llm.answer(question: "試験", context: "", history: "", onText: { _ in
        preconditionFailure("Disabled Live published text")
      }, authorize: { preconditionFailure("Disabled Live began authorization") })
      precondition(result.failure == .engineNotReady)
    }
    precondition(LocalVoiceModel.reads == 0)
    let store = LocalVoiceModelStore()
    let reads = LocalVoiceModel.reads
    for _ in 0..<100 { store.install() }
    precondition(LocalVoiceModel.reads == reads)
    precondition(!store.isInstalled && !store.isDownloading && !store.isVerifying)
    precondition(store.progress == 0 && store.errorMessage == nil)
    print("DisabledLiveChecks: passed (100 prepare/answer/install refusals, zero native/disk/network access or callbacks)")
  }
}
