import Foundation

/// Asks a provider's API for an answer using the person's own key.
enum CloudAIService {
  enum Failure: Error {
    case missingKey
    case unsupported
    case http
    case empty
  }

  static func answer(
    question: String,
    scopeLabel: String,
    context: String,
    provider: CloudProvider
  ) async throws -> String {
    guard let key = KeychainStore.string(forKey: "ai.\(provider.rawValue)"), !key.isEmpty else {
      throw Failure.missingKey
    }

    let system = "あなたは会議の記録を要約して答えるアシスタントです。短い日本語で、与えられた記録だけに沿って答えます。"
    let user = """
    対象: \(scopeLabel)

    \(context.isEmpty ? "" : "記録:\n\(context)\n")
    質問: \(question)
    記録に基づいて簡潔に答えてください。記録に無いことは推測せず、無いと伝えてください。
    """

    switch provider {
    case .openAI:
      return try await openAI(system: system, user: user, key: key)
    case .anthropic:
      return try await anthropic(system: system, user: user, key: key)
    case .google, .deepgram:
      throw Failure.unsupported
    }
  }

  private static func openAI(system: String, user: String, key: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": "gpt-4o-mini",
      "temperature": 0.2,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user]
      ]
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
    guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
      throw Failure.empty
    }
    return text
  }

  private static func anthropic(system: String, user: String, key: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": "claude-3-5-haiku-latest",
      "max_tokens": 500,
      "system": system,
      "messages": [["role": "user", "content": user]]
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
    guard let text = decoded.content.first?.text, !text.isEmpty else {
      throw Failure.empty
    }
    return text
  }

  private static func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw Failure.http
    }
  }
}

private struct OpenAIResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable { var content: String }
    var message: Message
  }
  var choices: [Choice]
}

private struct AnthropicResponse: Decodable {
  struct Block: Decodable { var text: String? }
  var content: [Block]
}
