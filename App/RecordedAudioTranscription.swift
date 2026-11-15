import AVFoundation
import Foundation

/// Saved recordings share the source import's immutable input, bounded export
/// and settled-prefix store. Live display text is never treated as complete.
enum RecordedAudioTranscription {
  static func transcribe(_ url: URL, locale: Locale, vocabulary: [String],
                         checkpointStore: SourceMediaCheckpointStore = .shared,
                         staging: SourceMediaStaging = .shared,
                         preparationPolicy: RecordedAudioPreparationPolicy = .validated,
                         checkReadiness: @escaping @Sendable () throws -> Void = { try AudioProcessingReadiness.check() },
                         recognize: @escaping @Sendable (URL) async -> TranscriptionOutcome) async -> TranscriptionOutcome {
    await transcribe(.file(url), locale: locale, vocabulary: vocabulary, checkpointStore: checkpointStore,
      staging: staging, preparationPolicy: preparationPolicy, checkReadiness: checkReadiness, recognize: recognize)
  }

  static func transcribe(_ input: RecordedAudioInput, locale: Locale, vocabulary: [String],
                         checkpointStore: SourceMediaCheckpointStore = .shared,
                         staging: SourceMediaStaging = .shared,
                         preparationPolicy: RecordedAudioPreparationPolicy = .validated,
                         checkReadiness: @escaping @Sendable () throws -> Void = { try AudioProcessingReadiness.check() },
                         recognize: @escaping @Sendable (URL) async -> TranscriptionOutcome) async -> TranscriptionOutcome {
    do {
      return try await AudioProcessingDiagnostics.trace(.recordedTranscription) {
        let diagnostic = AudioProcessingDiagnostics.current
        let queued = diagnostic?.begin(.queue)
        return try await SourceProcessingQueue.shared.perform {
          diagnostic?.end(queued, outcome: .success)
          return try await run(input, locale: locale, vocabulary: vocabulary, store: checkpointStore,
            staging: staging, preparationPolicy: preparationPolicy, checkReadiness: checkReadiness, recognize: recognize)
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

  private static func run(_ input: RecordedAudioInput, locale: Locale, vocabulary: [String],
                          store: SourceMediaCheckpointStore, staging: SourceMediaStaging,
                          preparationPolicy: RecordedAudioPreparationPolicy,
                          checkReadiness: @escaping @Sendable () throws -> Void,
                          recognize: @Sendable (URL) async -> TranscriptionOutcome) async throws -> TranscriptionOutcome {
    let scopeURL: URL = switch input { case .file(let url): url; case .parts(_, let directory): directory }
    let scoped = scopeURL.startAccessingSecurityScopedResource()
    defer { if scoped { scopeURL.stopAccessingSecurityScopedResource() } }
    let session = store.begin()
    let stage = try await staging.acquire(inputBytes: input.byteCount())
    defer { stage.remove() }
    let prepared = try await input.prepare(in: stage.directory)
    let asset = prepared.asset
    let duration = prepared.duration
    let diagnostic = AudioProcessingDiagnostics.current
    diagnostic?.setAudioSeconds(duration)
    let chunks = try SourceMediaChunk.plan(duration: duration)
    let key = try SourceMediaCheckpointStore.key(fingerprint: prepared.fingerprint,
      suffix: prepared.suffix, locale: locale, vocabulary: vocabulary, pipeline: prepared.pipeline)
    let checkpoint = store.load(key, duration: duration, session: session)
    var segments = checkpoint?.segments ?? []
    var completed = checkpoint?.completedChunks ?? 0
    var revisions = checkpoint?.chunkRevisions
    diagnostic?.chunks(reused: completed, completed: completed)
    return try await withThrowingTaskGroup(of: SourceMediaAudioLease.self) { pending in
      defer { pending.cancelAll() }
      var preparedIndex: Int?
      for index in completed..<chunks.count {
        let chunk = chunks[index]
        let segmentOffset = segments.count
        try Task.checkCancellation()
        let audio: SourceMediaAudioLease
        if preparedIndex == index {
          guard let next = try await pending.next() else { throw SourceMediaFailure.invalidTemporaryFile }
          audio = next
          preparedIndex = nil
        } else {
          audio = try await prepare(chunk, index: index, asset: asset, directory: stage.directory,
            checkReadiness: checkReadiness)
        }
        defer { audio.remove() }
        try Task.checkCancellation()
        try checkReadiness()
        if index + 1 < chunks.count, preparationPolicy.shouldPrepareNext(in: stage.directory) {
          let nextIndex = index + 1
          let nextChunk = chunks[nextIndex]
          pending.addTask {
            try await prepare(nextChunk, index: nextIndex, asset: asset, directory: stage.directory,
              checkReadiness: checkReadiness)
          }
          preparedIndex = nextIndex
        }
        let outcome: TranscriptionOutcome
        do {
          if AudioProcessingDiagnostics.inspectsSignal {
            do { _ = try AudioSignalInspector.inspect(audio.url) }
            catch is CancellationError { throw CancellationError() }
            catch { }
          }
          try Task.checkCancellation()
          try checkReadiness()
          outcome = await recognize(audio.url)
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
        var prefix = SourceMediaCheckpoint(duration: duration, completedChunks: completed, blocks: [],
          segments: segments, chunkRevisions: revisions)
        prefix.recordSettledChunk(index: index, segmentRange: segmentOffset..<segments.count, key: key)
        revisions = prefix.chunkRevisions
        guard prefix.isValid(for: duration) else { throw SourceMediaFailure.invalidTranscript }
        guard try prefix.persistenceData(maximumBytes: SourceExtractionPersistence.maximumEntryBytes) != nil else {
          throw SourceMediaFailure.transcriptTooLarge
        }
        store.save(prefix, key: key, session: session)
      }
      try Task.checkCancellation()
      let verification = diagnostic?.begin(.verification)
      for snapshot in prepared.snapshots { try snapshot.verifyOriginal() }
      diagnostic?.end(verification, outcome: .success)
      return segments.isEmpty ? .nothingRecognized : .segments(segments)
    }
  }

  private static func prepare(_ chunk: SourceMediaChunk, index: Int, asset: AVAsset, directory: URL,
                              checkReadiness: @Sendable () throws -> Void) async throws -> SourceMediaAudioLease {
    try Task.checkCancellation()
    try checkReadiness()
    guard try SourceMediaStaging.availableBytes(directory) >= SourceMediaStaging.minimumAvailableBytes else {
      throw SourceMediaFailure.capacity
    }
    guard let export = SourceMediaAudioExport(asset: asset, temporaryDirectory: directory, chunk: chunk) else {
      throw SourceMediaFailure.invalidTemporaryFile
    }
    let audio = SourceMediaAudioLease(url: directory.appendingPathComponent("chunk-\(index).m4a"))
    try await export.write(to: audio.url, stageDirectory: directory)
    try Task.checkCancellation()
    return audio
  }
}
