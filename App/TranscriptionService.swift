import AVFAudio
import CoreMedia
import Foundation
import Speech

enum TranscriptionOutcome {
  case segments([TranscriptSegment])
  /// The engine ran and settled, but understood nothing: silence, or no speech
  /// in a language it can handle.
  case nothingRecognized
  /// No engine can run here — missing assets, an unsupported locale, or an
  /// engine that is not wired yet.
  case unavailable
  /// An engine ran but failed. `message` explains why and how to retry.
  case failed(String)
  /// The work was stopped before it produced anything. Nothing is applied and
  /// the audio is kept.
  case cancelled
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
        do {
          switch try await SpeechAnalyzerTranscriber.transcribe(
            fileURL: fileURL,
            locale: language.locale
          ) {
          case .segments(let segments):
            return .segments(segments)
          case .nothingRecognized:
            return .nothingRecognized
          case .cancelled:
            return .cancelled
          }
        } catch SpeechAnalyzerTranscriber.Failure.unsupported {
          return .unavailable
        } catch is CancellationError {
          return .cancelled
        } catch {
          return .failed("文字起こしに失敗しました。音声は保存されています。もう一度お試しください。")
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
  /// What one run over a saved file produced.
  enum Outcome {
    case segments([TranscriptSegment])
    case nothingRecognized
    case cancelled
  }

  enum Failure: Error {
    /// No engine can run here (device, OS, or the language asked for).
    case unsupported
    /// The engine ran and failed.
    case failed(String)
  }

  static func transcribe(fileURL: URL, locale: Locale) async throws -> Outcome {
    guard SpeechTranscriber.isAvailable,
          let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
      throw Failure.unsupported
    }

    // Saved audio is transcribed once, so volatile progress is not asked for:
    // with no `volatileResults`, a phrase is only reported once it has settled
    // and cannot be withdrawn. `audioTimeRange` keeps each result's time.
    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      transcriptionOptions: [.etiquetteReplacements],
      // No `volatileResults`: a saved file is transcribed once, so only settled
      // results are wanted. `audioTimeRange` keeps each result's time.
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )

    // Pull the model down once, then it is reused.
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }

    let audioFile = try AVAudioFile(forReading: fileURL)
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    // Lines are appended as they settle. Nothing accumulates the raw results, so
    // a long recording does not hold every progress string it ever produced.
    let collect = Task { () -> [TranscriptSegment] in
      var segments: [TranscriptSegment] = []
      for try await result in transcriber.results {
        let update = SpeechTranscriptionUpdate(
          text: String(result.text.characters),
          timestamp: CMTimeGetSeconds(result.range.start),
          isFinal: result.isFinal
        )
        if let segment = SpeechTranscriptionSegments.segment(from: update) {
          segments.append(segment)
        }
      }
      return segments
    }
    // Whatever happens below — the parent being cancelled, an engine failure, or
    // a return — the collector does not outlive this call.
    defer { collect.cancel() }

    do {
      _ = try await analyzer.analyzeSequence(from: audioFile)
      try await analyzer.finalizeAndFinishThroughEndOfInput()
    } catch {
      // End the analysis session as well as the collector, so a cancelled or
      // failed run leaves no session behind.
      await analyzer.cancelAndFinishNow()
      if error is CancellationError { throw CancellationError() }
      throw Failure.failed("\(error)")
    }

    let segments: [TranscriptSegment]
    do {
      segments = try await collect.value
    } catch is CancellationError {
      await analyzer.cancelAndFinishNow()
      return .cancelled
    } catch {
      await analyzer.cancelAndFinishNow()
      throw Failure.failed("\(error)")
    }
    // The parent may have been cancelled while the results were being gathered.
    if Task.isCancelled {
      await analyzer.cancelAndFinishNow()
      return .cancelled
    }
    return segments.isEmpty ? .nothingRecognized : .segments(segments)
  }

}
