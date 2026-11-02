import AVFoundation
import Foundation

/// Saved recordings share the source import's immutable input, bounded export
/// and settled-prefix store. Live display text is never treated as complete.
enum RecordedAudioTranscription {
  static func transcribe(_ url: URL, locale: Locale, vocabulary: [String],
                         checkpointStore: SourceMediaCheckpointStore = .shared,
                         staging: SourceMediaStaging = .shared,
                         checkReadiness: @escaping @Sendable () throws -> Void = { try AudioProcessingReadiness.check() },
                         recognize: @escaping @Sendable (URL) async -> TranscriptionOutcome) async -> TranscriptionOutcome {
    do {
      return try await AudioProcessingDiagnostics.trace(.recordedTranscription) {
        let diagnostic = AudioProcessingDiagnostics.current
        let queued = diagnostic?.begin(.queue)
        return try await SourceProcessingQueue.shared.perform {
          diagnostic?.end(queued, outcome: .success)
          return try await run(url, locale: locale, vocabulary: vocabulary, store: checkpointStore,
            staging: staging, checkReadiness: checkReadiness, recognize: recognize)
        }
      } outcome: { $0.diagnosticOutcome }
    } catch is CancellationError {
      return .cancelled
    } catch let failure as SourceMediaFailure {
      return .failed(failure.localizedDescription)
    } catch {
      return .failed("音声を準備できませんでした。原本は保存されています。空き容量とファイルを確認して再試行してください。")
    }
  }

  private static func run(_ url: URL, locale: Locale, vocabulary: [String],
                          store: SourceMediaCheckpointStore, staging: SourceMediaStaging,
                          checkReadiness: @Sendable () throws -> Void,
                          recognize: @Sendable (URL) async -> TranscriptionOutcome) async throws -> TranscriptionOutcome {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let session = store.begin()
    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
    let stage = try await staging.acquire(inputBytes: Int64(bytes))
    defer { stage.remove() }
    let snapshot = try SourceMediaSnapshot(url, directory: stage.directory,
      maximumBytes: Int(SourceMediaStaging.maximumInputBytes))
    let asset = AVURLAsset(url: snapshot.url)
    let duration = try await asset.load(.duration).seconds
    let diagnostic = AudioProcessingDiagnostics.current
    diagnostic?.setAudioSeconds(duration)
    let chunks = try SourceMediaChunk.plan(duration: duration)
    let key = try SourceMediaCheckpointStore.key(fingerprint: snapshot.fingerprint,
      suffix: url.pathExtension.lowercased(), locale: locale, vocabulary: vocabulary,
      pipeline: "recording-speech-analyzer-v1")
    let checkpoint = store.load(key, duration: duration, session: session)
    var segments = checkpoint?.segments ?? []
    var completed = checkpoint?.completedChunks ?? 0
    diagnostic?.chunks(reused: completed, completed: completed)
    for chunk in chunks.dropFirst(completed) {
      try Task.checkCancellation()
      try checkReadiness()
      guard try SourceMediaStaging.availableBytes(stage.directory) >= SourceMediaStaging.minimumAvailableBytes else {
        throw SourceMediaFailure.capacity
      }
      guard let export = SourceMediaAudioExport(asset: asset, temporaryDirectory: stage.directory, chunk: chunk) else {
        throw SourceMediaFailure.invalidTemporaryFile
      }
      let outcome: TranscriptionOutcome
      do {
        defer { try? FileManager.default.removeItem(at: stage.audioURL) }
        try await export.write(to: stage.audioURL, stageDirectory: stage.directory)
        try checkReadiness()
        if AudioProcessingDiagnostics.inspectsSignal {
          do { _ = try AudioSignalInspector.inspect(stage.audioURL) }
          catch is CancellationError { throw CancellationError() }
          catch { }
        }
        try Task.checkCancellation()
        try checkReadiness()
        outcome = await recognize(stage.audioURL)
      }
      try Task.checkCancellation()
      switch outcome {
      case .segments(let local):
        for var segment in local {
          guard segment.timestamp.isFinite, segment.timestamp >= 0,
                segment.timestamp <= chunk.duration + 1,
                segment.endTime.map({ $0.isFinite && $0 >= segment.timestamp && $0 <= chunk.duration + 1 }) ?? true else {
            throw SourceMediaFailure.invalidTranscript
          }
          segment.timestamp = chunk.start + min(segment.timestamp, chunk.duration)
          segment.endTime = segment.endTime.map { chunk.start + min($0, chunk.duration) }
          segment.recognitionEngine = "apple"
          segment.recognitionModel = "SpeechAnalyzer"
          segment.recognitionLanguage = locale.identifier
          segments.append(segment)
        }
      case .nothingRecognized: break
      case .failed, .unavailable, .cancelled: return outcome
      }
      completed += 1
      diagnostic?.chunks(completed: completed)
      let prefix = SourceMediaCheckpoint(duration: duration, completedChunks: completed, blocks: [], segments: segments)
      guard prefix.isValid(for: duration) else { throw SourceMediaFailure.invalidTranscript }
      guard try JSONEncoder().encode(prefix).count <= SourceExtractionPersistence.maximumEntryBytes else {
        throw SourceMediaFailure.transcriptTooLarge
      }
      store.save(prefix, key: key, session: session)
    }
    try Task.checkCancellation()
    let verification = diagnostic?.begin(.verification)
    try snapshot.verifyOriginal()
    diagnostic?.end(verification, outcome: .success)
    return segments.isEmpty ? .nothingRecognized : .segments(segments)
  }
}
