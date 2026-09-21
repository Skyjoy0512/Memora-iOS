import Foundation

/// Transcribes a recording with a provider's API using the person's own key.
enum CloudTranscriptionService {
  enum Failure: Error {
    case missingKey
    case unsupported
    case http
    case empty
    /// The file is larger than the provider accepts, in bytes.
    case tooLarge(Int)
  }

  /// Upload limits from the providers' documentation. OpenAI's audio
  /// transcriptions endpoint accepts 25 MB; Deepgram's pre-recorded endpoint
  /// accepts up to 2 GB per request. Files are checked before anything is sent,
  /// so an oversized recording is explained rather than failing mid-upload.
  private static let openAILimit = 25 * 1024 * 1024
  private static let deepgramLimit = 2 * 1024 * 1024 * 1024

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
    try checkSize(fileURL, limit: openAILimit)

    let boundary = "Boundary-\(UUID().uuidString)"
    let mime = MediaFiles.mimeType(for: fileURL)

    // The multipart body is assembled in a temporary file: a long recording is
    // never read into memory.
    let bodyURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("openai-upload-\(UUID().uuidString).body")
    defer { try? FileManager.default.removeItem(at: bodyURL) }

    guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
      throw Failure.unsupported
    }
    let body = try FileHandle(forWritingTo: bodyURL)
    defer { try? body.close() }

    func write(_ string: String) {
      body.write(Data(string.utf8))
    }
    func copyFileContents() throws {
      let input = try FileHandle(forReadingFrom: fileURL)
      defer { try? input.close() }
      while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
        body.write(chunk)
      }
    }

    write("--\(boundary)\r\n")
    write("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
    write("whisper-1\r\n")
    write("--\(boundary)\r\n")
    write("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
    write("\(language)\r\n")
    write("--\(boundary)\r\n")
    write("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(fileURL.pathExtension)\"\r\n")
    write("Content-Type: \(mime)\r\n\r\n")
    try copyFileContents()
    write("\r\n--\(boundary)--\r\n")
    try body.close()

    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
    try validate(response)

    guard let decoded = try? JSONDecoder().decode(OpenAITranscript.self, from: data) else {
      throw Failure.empty
    }
    return decoded.text
  }

  private static func deepgram(fileURL: URL, language: String, key: String) async throws -> String {
    try checkSize(fileURL, limit: deepgramLimit)

    var components = URLComponents(string: "https://api.deepgram.com/v1/listen")
    components?.queryItems = [
      URLQueryItem(name: "language", value: language),
      URLQueryItem(name: "punctuate", value: "true")
    ]

    guard let url = components?.url else { throw Failure.unsupported }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
    request.setValue(MediaFiles.mimeType(for: fileURL), forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
    try validate(response)

    let decoded = try JSONDecoder().decode(DeepgramTranscript.self, from: data)
    return decoded.results?.channels.first?.alternatives.first?.transcript ?? ""
  }

  /// Refuses a file that is too large before any of it is sent.
  private static func checkSize(_ fileURL: URL, limit: Int) throws {
    guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
      throw Failure.unsupported
    }
    guard size <= limit else {
      throw Failure.tooLarge(limit)
    }
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
