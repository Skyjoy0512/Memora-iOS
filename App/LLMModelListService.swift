import Foundation

/// Loads the models a key can actually call, so the picker is not limited to
/// suggestions that may have been renamed since this build.
enum LLMModelListService {
  /// Ids that are not chat models (embeddings, speech, images, moderation),
  /// which the chat endpoint would refuse.
  private static let excludedFragments = [
    "embed", "tts", "whisper", "transcribe", "dall-e", "image", "moderation",
    "audio", "realtime", "speech", "search", "rerank", "ocr", "babbage", "davinci"
  ]

  static func fetchModels(for provider: LLMProvider) async throws -> [String] {
    guard let key = KeychainStore.string(forKey: provider.keychainAccount), !key.isEmpty else {
      throw AIAnswerFailure.missingKey
    }

    var request = URLRequest(url: provider.baseURL.appendingPathComponent("models"))
    request.timeoutInterval = 30
    if provider.usesAnthropicAPI {
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
      request.url = URL(string: request.url!.absoluteString + "?limit=100")
    } else {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    try CloudAIService.validate(response)
    let decoded = try JSONDecoder().decode(ModelList.self, from: data)
    let ids = decoded.data.map { id in
      // Gemini lists its models as "models/<id>" but is called with the bare id.
      id.id.hasPrefix("models/") ? String(id.id.dropFirst("models/".count)) : id.id
    }
    return Array(Set(ids.filter { id in
      let lowered = id.lowercased()
      return !excludedFragments.contains { lowered.contains($0) }
    }))
    .sorted()
  }
}

private struct ModelList: Decodable {
  struct Model: Decodable { var id: String }
  var data: [Model]
}
