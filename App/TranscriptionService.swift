import AVFAudio
import CoreMedia
import Foundation
import Speech

enum TranscriptionOutcome {
  case segments([TranscriptSegment])
  /// No engine can run here — missing assets, an unsupported locale, or an
  /// engine that is not wired yet.
  case unavailable
  /// An engine ran but failed. `message` explains why and how to retry.
  case failed(String)
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
      do {
        let segments = try await CloudTranscriptionService.transcribe(
          fileURL: fileURL,
          locale: language.locale,
          provider: provider
        )
        return .segments(segments)
      } catch CloudTranscriptionService.Failure.missingKey {
        return .failed("クラウド文字起こしのAPIキーが設定されていません。設定から入力してください。")
      } catch CloudTranscriptionService.Failure.unsupported {
        return .failed("このプロバイダーは文字起こしに対応していません。設定で別のプロバイダーを選んでください。")
      } catch CloudTranscriptionService.Failure.empty {
        return .failed("音声から発言を取得できませんでした。音声を確認して再試行してください。")
      } catch CloudTranscriptionService.Failure.tooLarge(let limit) {
        return .failed("音声が大きすぎます（上限\(limit / (1024 * 1024))MB）。ファイルを分割してお試しください。")
      } catch {
        return .failed("クラウド文字起こしに失敗しました。通信環境とAPIキーを確認して再試行してください。")
      }

    case .onDevice:
      // Whisper still needs a bundled model; nothing can run here yet.
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
      var updates: [SpeechUpdate] = []
      for try await result in transcriber.results {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        let seconds = CMTimeGetSeconds(result.range.start)
        updates.append(
          SpeechUpdate(
            text: text,
            timestamp: seconds.isFinite ? seconds : 0,
            isFinal: result.isFinal
          )
        )
      }
      return SpeechTranscriptionCollapse.collapse(updates)
    }

    _ = try await analyzer.analyzeSequence(from: audioFile)
    try await analyzer.finalizeAndFinishThroughEndOfInput()

    let segments = try await collect.value
    guard !segments.isEmpty else { throw Failure.empty }
    return segments
  }

}
