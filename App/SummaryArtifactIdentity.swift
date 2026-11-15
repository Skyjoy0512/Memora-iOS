import CryptoKit
import Foundation

enum SummaryArtifactIdentity {
  /// The caller binds only the actual part metadata; final integration always reruns.
  /// Presentation length/order are absent from the part analysis prompt.
  static func identity(scope: SummaryArtifactScope, input: MeetingSummaryInput, llm: LLMSelection, segments: [TranscriptSegment]? = nil) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let scopeData = try? encoder.encode(scope),
          let selection = try? encoder.encode(llm) else { return nil }
    let capability = ModelCapabilityRegistry.capabilities(for: llm)
    let budget = "\(capability.contextWindowTokens):\(capability.maximumOutputTokens):\(ModelCapabilityRegistry.outputReservation(for: llm))"
    let fields: [Data] = [scopeData, selection, Data(budget.utf8),
      Data(input.preferences.processingMode.rawValue.utf8), Data(SummaryPrompt.system.utf8),
      Data("summary-part-analysis.v2".utf8)]
    // Length-prefix framing avoids ambiguous concatenations. Secrets are hashed
    // in memory and never retained in the artifact or a diagnostic.
    var digest = SHA256()
    for field in fields {
      digest.update(data: Data("\(field.count):".utf8))
      digest.update(data: field)
    }
    for segment in segments ?? input.transcript {
      guard let data = try? encoder.encode(segment) else { return nil }
      digest.update(data: Data("\(data.count):".utf8))
      digest.update(data: data)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
  static func key(identity: String, prompt: String) -> String {
    SHA256.hash(data: Data((identity + ":" + prompt).utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
