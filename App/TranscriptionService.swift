import AVFAudio
import CoreMedia
import Foundation
import Speech

enum TranscriptionOutcome {
  case segments([TranscriptSegment])
  /// No engine could run here — the caller falls back to its placeholder.
  case unavailable
}

/// Transcribes audio with the chosen engine and falls back when it cannot run
/// here (missing assets, unsupported locale, or an engine that is not wired yet).
enum TranscriptionService {
  static func transcribe(fileURL: URL?) async -> TranscriptionOutcome {
    guard let fileURL else { return .unavailable }

    let defaults = UserDefaults.standard
    let engine = TranscriptionEngine(
      rawValue: defaults.string(forKey: "memora.transcriptionEngine") ?? ""
    ) ?? .automatic
    let language = RecognitionLanguage(
      rawValue: defaults.string(forKey: "memora.transcriptionLanguage") ?? ""
    ) ?? .japanese

    switch engine {
    case .speechAnalyzer, .automatic:
      if #available(iOS 26.0, *) {
        if let segments = try? await SpeechAnalyzerTranscriber.transcribe(
          fileURL: fileURL,
          locale: language.locale
        ) {
          return .segments(segments)
        }
      }
      return .unavailable

    case .cloud:
      let provider = CloudProvider(
        rawValue: defaults.string(forKey: "memora.transcriptionProvider") ?? ""
      ) ?? .openAI
      if let segments = try? await CloudTranscriptionService.transcribe(
        fileURL: fileURL,
        locale: language.locale,
        provider: provider
      ) {
        return .segments(segments)
      }
      return .unavailable

    case .onDevice:
      // Whisper still needs a bundled model; the caller falls back for now.
      return .unavailable
    }
  }
}

/// Apple's on-device `SpeechAnalyzer`, available from iOS 26.
@available(iOS 26.0, *)
private enum SpeechAnalyzerTranscriber {
  enum Failure: Error {
    case unsupported
    case empty
  }

  static func transcribe(fileURL: URL, locale: Locale) async throws -> [TranscriptSegment] {
    guard SpeechTranscriber.isAvailable,
          let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
      throw Failure.unsupported
    }

    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      preset: .timeIndexedProgressiveTranscription
    )

    // Pull the model down once, then it is reused.
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }

    let audioFile = try AVAudioFile(forReading: fileURL)
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    let collect = Task { () -> [TranscriptSegment] in
      var segments: [TranscriptSegment] = []
      for try await result in transcriber.results {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        let seconds = CMTimeGetSeconds(result.range.start)
        segments.append(
          TranscriptSegment(
            id: UUID(),
            speaker: "話者",
            speakerIsCertain: false,
            timestamp: seconds.isFinite ? seconds : 0,
            text: text
          )
        )
      }
      return segments
    }

    _ = try await analyzer.analyzeSequence(from: audioFile)
    try await analyzer.finalizeAndFinishThroughEndOfInput()

    let segments = try await collect.value
    guard !segments.isEmpty else { throw Failure.empty }
    return segments
  }
}
