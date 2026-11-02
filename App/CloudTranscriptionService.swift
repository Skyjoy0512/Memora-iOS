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
    provider: CloudProvider,
    vocabulary: [String] = [],
    authorize: @escaping @MainActor @Sendable () -> Bool
  ) async throws -> [TranscriptSegment] {
    guard let key = KeychainStore.string(forKey: "transcription.\(provider.rawValue)"), !key.isEmpty else {
      throw Failure.missingKey
    }

    let language = locale.language.languageCode?.identifier ?? "ja"

    let segments: [TranscriptSegment]
    switch provider {
    case .openAI:
      segments = try await openAI(fileURL: fileURL, language: language, key: key, vocabulary: vocabulary, authorize: authorize)
    case .deepgram:
      segments = try await deepgram(fileURL: fileURL, language: language, key: key, vocabulary: vocabulary, authorize: authorize)
    case .anthropic, .google:
      throw Failure.unsupported
    }

    try Task.checkCancellation()
    guard !segments.isEmpty else { throw Failure.empty }
    return segments
  }

  private static func openAI(fileURL: URL, language: String, key: String, vocabulary: [String],
                             authorize: @MainActor @Sendable () -> Bool) async throws -> [TranscriptSegment] {
    try checkSize(fileURL, limit: openAILimit)

    let boundary = "Boundary-\(UUID().uuidString)"
    let mime = MediaFiles.mimeType(for: fileURL)

    // The multipart body is assembled in a temporary file: a long recording is
    // never read into memory.
    let bodyURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("openai-upload-\(UUID().uuidString).body")
    defer { try? FileManager.default.removeItem(at: bodyURL) }

    guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil,
      attributes: [.posixPermissions: 0o600]) else {
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
        try Task.checkCancellation()
        try body.write(contentsOf: chunk)
      }
    }

    write("--\(boundary)\r\n")
    write("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
    write("whisper-1\r\n")
    write("--\(boundary)\r\n")
    write("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
    write("verbose_json\r\n")
    write("--\(boundary)\r\n")
    write("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n")
    write("segment\r\n")
    write("--\(boundary)\r\n")
    write("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
    write("\(language)\r\n")
    if !vocabulary.isEmpty {
      // Whisper follows the spelling of words that appear in its prompt.
      write("--\(boundary)\r\n")
      write("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
      write("用語: \(vocabulary.joined(separator: "、"))\r\n")
    }
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

    try Task.checkCancellation()
    guard await authorize() else { throw CancellationError() }
    let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
    try validate(response)

    return try CloudTranscriptDecoder.openAI(data, language: language)
  }

  private static func deepgram(fileURL: URL, language: String, key: String, vocabulary: [String],
                               authorize: @MainActor @Sendable () -> Bool) async throws -> [TranscriptSegment] {
    try checkSize(fileURL, limit: deepgramLimit)

    var components = URLComponents(string: "https://api.deepgram.com/v1/listen")
    components?.queryItems = [
      URLQueryItem(name: "model", value: "nova-3"),
      URLQueryItem(name: "language", value: language),
      URLQueryItem(name: "punctuate", value: "true"),
      URLQueryItem(name: "utterances", value: "true"),
      URLQueryItem(name: "mip_opt_out", value: "true")
    ] + vocabulary.prefix(50).map { URLQueryItem(name: "keyterm", value: $0) }

    guard let url = components?.url else { throw Failure.unsupported }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
    request.setValue(MediaFiles.mimeType(for: fileURL), forHTTPHeaderField: "Content-Type")

    try Task.checkCancellation()
    guard await authorize() else { throw CancellationError() }
    let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
    try validate(response)

    return try CloudTranscriptDecoder.deepgram(data, language: language)
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
