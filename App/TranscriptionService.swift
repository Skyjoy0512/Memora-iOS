import AVFAudio
import CoreMedia
import Foundation
import Speech

/// Transcribes audio with the chosen engine and falls back when it cannot run
/// here (missing assets, unsupported locale, or an engine that is not wired yet).
enum TranscriptionService {
  /// Choose the vocabulary at dispatch, even when engine settings changed while queued.
  static func transcribe(fileURL: URL?, vocabulary: [String] = [], cloudVocabulary: [String] = [], onDeviceOnly: Bool = false,
                         locale: Locale? = nil, isPreparedChunk: Bool = false,
                         recordingManifest: RecordingAudioManifest? = nil, recordingDirectory: URL? = nil,
                         authorizeCloud: (@MainActor @Sendable () -> Bool)? = nil) async -> TranscriptionOutcome {
    let isSegmented = (recordingManifest?.parts.count ?? 0) > 1
    guard fileURL != nil || isSegmented else { return .unavailable }

    let defaults = UserDefaults.standard
    let engine = onDeviceOnly ? .automatic : TranscriptionEngine(
      rawValue: defaults.string(forKey: "memora.transcriptionEngine") ?? ""
    ) ?? .automatic
    let language = RecognitionLanguage(
      rawValue: defaults.string(forKey: "memora.transcriptionLanguage") ?? ""
    ) ?? .japanese
    let locale = locale ?? language.locale

    switch engine {
    case .speechAnalyzer, .automatic:
      if !isPreparedChunk {
        if isSegmented {
          guard let recordingManifest, let recordingDirectory else { return .unavailable }
          return await RecordedAudioTranscription.transcribe(.parts(recordingManifest, directory: recordingDirectory),
            locale: locale, vocabulary: vocabulary) { chunkURL in
              await transcribe(fileURL: chunkURL, vocabulary: vocabulary, onDeviceOnly: true,
                locale: locale, isPreparedChunk: true)
            }
        }
        guard let fileURL else { return .unavailable }
        return await RecordedAudioTranscription.transcribe(fileURL, locale: locale, vocabulary: vocabulary) { chunkURL in
          await transcribe(fileURL: chunkURL, vocabulary: vocabulary, onDeviceOnly: true,
            locale: locale, isPreparedChunk: true)
        }
      }
      guard let fileURL else { return .unavailable }
      if #available(iOS 26.0, *) {
        do {
          switch try await SpeechAnalyzerTranscriber.transcribe(
            fileURL: fileURL,
            locale: locale,
            vocabulary: vocabulary
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
      guard !isSegmented else {
        return .failed("分割録音の文字起こしは端末内で利用できます。設定で端末内の文字起こしを選んで再試行してください。")
      }
      guard let fileURL else { return .unavailable }
      guard let authorizeCloud, await authorizeCloud() else { return .failed(RecordAccessPolicy.refusal) }
      let provider = CloudProvider(
        rawValue: defaults.string(forKey: "memora.transcriptionProvider") ?? ""
      ) ?? .openAI
      do {
        let segments = try await CloudTranscriptionService.transcribe(
          fileURL: fileURL,
          locale: locale,
          provider: provider,
          vocabulary: cloudVocabulary,
          authorize: authorizeCloud
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
      } catch is CancellationError {
        return .cancelled
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

  static func transcribe(fileURL: URL, locale: Locale, vocabulary: [String]) async throws -> Outcome {
    let diagnostic = AudioProcessingDiagnostics.current
    diagnostic?.setEngine(.appleSpeech)
    let preparation = diagnostic?.begin(.modelPreparation)
    let interval = AudioProcessingDiagnostics.signposter.beginInterval("SavedAudioTranscription")
    defer { AudioProcessingDiagnostics.signposter.endInterval("SavedAudioTranscription", interval) }
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
    try Task.checkCancellation()

    // Pull the model down once, then it is reused.
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
    try Task.checkCancellation()

    let audioFile = try AVAudioFile(forReading: fileURL)
    diagnostic?.end(preparation, outcome: .success)
    let recognition = diagnostic?.begin(.recognition, audioSeconds: Double(audioFile.length) / audioFile.processingFormat.sampleRate)
    var diagnosticOutcome: AudioDiagnosticReport.Outcome = .failed
    defer { diagnostic?.end(recognition, outcome: Task.isCancelled ? .cancelled : diagnosticOutcome) }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    if !vocabulary.isEmpty {
      // Names and terms the recogniser would otherwise not know.
      let context = AnalysisContext()
      context.contextualStrings[.general] = vocabulary
      try? await analyzer.setContext(context)
    }

    // Lines are appended as they settle. Nothing accumulates the raw results, so
    // a long recording does not hold every progress string it ever produced.
    let collect = Task { () -> [TranscriptSegment] in
      var segments: [TranscriptSegment] = []
      for try await result in transcriber.results {
        let update = SpeechTranscriptionUpdate(
          text: String(result.text.characters),
          timestamp: CMTimeGetSeconds(result.range.start),
          isFinal: result.isFinal,
          endTime: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
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
    diagnosticOutcome = segments.isEmpty ? .empty : .success
    return segments.isEmpty ? .nothingRecognized : .segments(segments)
  }

}
