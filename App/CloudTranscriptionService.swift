import Foundation

/// Transcribes a recording with a provider's API using the person's own key.
enum CloudTranscriptionService {
  enum Failure: Error {
    case missingKey
    case unsupported
    case http
    case empty
  }

  static func transcribe(
    fileURL: URL,
    locale: Locale,
    provider: CloudProvider
  ) async throws -> [TranscriptSegment] {
    guard let key = KeychainStore.string(forKey: "transcription.\(provider.rawValue)"), !key.isEmpty else {
      throw Failure.missingKey
    }

    let language = locale.language.languageCode?.identifier ?? "ja"

    let text: String
    switch provider {
    case .openAI:
      text = try await openAI(fileURL: fileURL, language: language, key: key)
    case .deepgram:
      text = try await deepgram(fileURL: fileURL, language: language, key: key)
    case .anthropic, .google:
      throw Failure.unsupported
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw Failure.empty }

    return [
      TranscriptSegment(
        id: UUID(),
        speaker: "話者",
        speakerIsCertain: false,
        timestamp: 0,
        text: trimmed
      )
    ]
  }

  private static func openAI(fileURL: URL, language: String, key: String) async throws -> String {
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let audio = try Data(contentsOf: fileURL)
    var body = Data()
    func append(_ string: String) {
      body.append(Data(string.utf8))
    }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
    append("whisper-1\r\n")

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
    append("\(language)\r\n")

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
    append("Content-Type: audio/mp4\r\n\r\n")
    body.append(audio)
    append("\r\n--\(boundary)--\r\n")

    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    guard let decoded = try? JSONDecoder().decode(OpenAITranscript.self, from: data) else {
      throw Failure.empty
    }
    return decoded.text
  }

  private static func deepgram(fileURL: URL, language: String, key: String) async throws -> String {
    var components = URLComponents(string: "https://api.deepgram.com/v1/listen")
    components?.queryItems = [
      URLQueryItem(name: "language", value: language),
      URLQueryItem(name: "punctuate", value: "true")
    ]

    guard let url = components?.url else { throw Failure.unsupported }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
    request.httpBody = try Data(contentsOf: fileURL)

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(DeepgramTranscript.self, from: data)
    return decoded.results?.channels.first?.alternatives.first?.transcript ?? ""
  }

  private static func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw Failure.http
    }
  }
}

private struct OpenAITranscript: Decodable {
  var text: String
}

private struct DeepgramTranscript: Decodable {
  struct Results: Decodable {
    struct Channel: Decodable {
      struct Alternative: Decodable { var transcript: String }
      var alternatives: [Alternative]
    }
    var channels: [Channel]
  }
  var results: Results?
}
