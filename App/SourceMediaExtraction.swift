import AVFoundation
import Foundation

enum SourceMediaExtraction {
  static func extract(_ url: URL, vocabulary: [String], speechLocale: Locale? = nil,
                      checkpointStore: SourceMediaCheckpointStore = .shared) async throws -> ProjectSourceExtractionResult {
    try await AudioProcessingDiagnostics.trace(.sourceExtraction) {
      try await perform(url, vocabulary: vocabulary, speechLocale: speechLocale, checkpointStore: checkpointStore)
    } outcome: { $0.blocks.isEmpty ? .empty : .success }
  }

  private static func perform(_ url: URL, vocabulary: [String], speechLocale: Locale?,
                              checkpointStore: SourceMediaCheckpointStore) async throws -> ProjectSourceExtractionResult {
    let diagnostic = AudioProcessingDiagnostics.current
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    try Task.checkCancellation()
    // Capture before the first suspension, including input copy. Deletion can
    // revoke this session even while the original's digest is still unknown.
    let session = checkpointStore.begin()
    let locale = speechLocale ?? (RecognitionLanguage(rawValue:
      UserDefaults.standard.string(forKey: "memora.transcriptionLanguage") ?? "") ?? .japanese).locale
    let stage = try await SourceMediaStaging.shared.acquire()
    defer { stage.remove() }
    let snapshot = try SourceMediaSnapshot(url, directory: stage.directory)
    let asset = AVURLAsset(url: snapshot.url)
    guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
      diagnostic?.finish(.unavailable)
      return .init(blocks: [], notice: "音声トラックがありません。映像の内容は解析していません。")
    }
    let duration = try await asset.load(.duration).seconds
    diagnostic?.setAudioSeconds(duration)
    let chunks = try SourceMediaChunk.plan(duration: duration)
    let key = try SourceMediaCheckpointStore.key(fingerprint: snapshot.fingerprint,
      suffix: url.pathExtension.lowercased(), locale: locale, vocabulary: vocabulary)
    let checkpoint = checkpointStore.load(key, duration: duration, session: session)
    var transcript = SourceMediaTranscript()
    try transcript.restore(checkpoint?.blocks ?? [])
    var completed = checkpoint?.completedChunks ?? 0
    diagnostic?.chunks(reused: completed, completed: completed)
    for chunk in chunks.dropFirst(completed) {
      try Task.checkCancellation()
      let outcome = try await transcribe(chunk, asset: asset, stage: stage, vocabulary: vocabulary, locale: locale)
      try Task.checkCancellation()
      switch outcome {
      case .segments(let segments): try transcript.append(segments, chunk: chunk)
      case .nothingRecognized: break
      // Never cache or summarize a successful prefix as the whole recording.
      case .failed(let message):
        diagnostic?.finish(.failed)
        return .init(blocks: [], notice: message)
      case .unavailable:
        diagnostic?.finish(.unavailable)
        return .init(blocks: [], notice: "この端末では端末内の文字起こしを利用できません。原本は保存されています。対応端末で再試行してください。")
      case .cancelled: throw CancellationError()
      }
      completed += 1
      diagnostic?.chunks(completed: completed)
      checkpointStore.save(.init(duration: duration, completedChunks: completed, blocks: transcript.blocks),
        key: key, session: session)
    }
    try Task.checkCancellation()
    let verification = diagnostic?.begin(.verification)
    try snapshot.verifyOriginal()
    diagnostic?.end(verification, outcome: .success)
    return .init(blocks: transcript.blocks,
      notice: transcript.blocks.isEmpty
        ? "音声から発言を読み取れませんでした。原本を確認して再試行できます。"
        : (SourceIntake.kind(for: url) == .video ? "音声の文字起こしです。映像の内容は解析していません。" : nil),
      coverage: .partial)
  }

  private static func transcribe(_ chunk: SourceMediaChunk, asset: AVAsset, stage: SourceMediaStageLease,
                                 vocabulary: [String], locale: Locale) async throws -> TranscriptionOutcome {
    // The immutable input stays protected by its lease. Only one exported
    // chunk exists, and recognition never outlives this scope.
    defer { try? FileManager.default.removeItem(at: stage.audioURL) }
    guard let export = SourceMediaAudioExport(asset: asset, temporaryDirectory: stage.directory, chunk: chunk) else {
      return .failed("この音声を解析できません。再生可能なファイルを追加してください。原本は保存されています。")
    }
    try await export.write(to: stage.audioURL, stageDirectory: stage.directory)
    if AudioProcessingDiagnostics.inspectsSignal {
      do { _ = try AudioSignalInspector.inspect(stage.audioURL) }
      catch is CancellationError { throw CancellationError() }
      catch { }
    }
    try Task.checkCancellation()
    // Importing a file is not permission to upload it to a speech provider.
    return await TranscriptionService.transcribe(fileURL: stage.audioURL, vocabulary: vocabulary,
      onDeviceOnly: true, locale: locale, isPreparedChunk: true)
  }
}
